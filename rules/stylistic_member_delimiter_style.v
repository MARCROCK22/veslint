module rules

import estree
import time
import x.json2

// Port of the `@stylistic/member-delimiter-style` rule of @stylistic/eslint-plugin 5.10.0, with its
// options (`multiline` and `singleline`, each with `delimiter` and `requireLast`, `overrides` for
// `interface` and `typeLiteral`, and `multilineDetection`) and its fixes: the delimiters after the
// members of interfaces and type literals.

const smds_messages = {
	'unexpectedComma': 'Unexpected separator (,).'
	'unexpectedSemi':  'Unexpected separator (;).'
	'expectedComma':   'Expected a comma.'
	'expectedSemi':    'Expected a semicolon.'
}

// SmdsOpts are the options of one kind of line (`opts` of checkLastToken).
struct SmdsOpts {
	delimiter    string
	require_last ?bool
	single_line  bool
}

struct SmdsOptions {
	interface_options    map[string]json2.Any
	type_literal_options map[string]json2.Any
	last_member          bool // multilineDetection: "last-member"
}

fn smds_options(given []json2.Any) !SmdsOptions {
	options := sty_options(given, [
		json2.Any({
			'multiline':          json2.Any({
				'delimiter':   json2.Any('semi')
				'requireLast': json2.Any(true)
			})
			'singleline':         json2.Any({
				'delimiter':   json2.Any('semi')
				'requireLast': json2.Any(false)
			})
			'multilineDetection': json2.Any('brackets')
		}),
	])
	base := sty_option_object(options, 0)
	overrides := sls_object(base['overrides'] or { json2.Any(json2.Null{}) })
	detection := base['multilineDetection'] or { json2.Any('') }
	return SmdsOptions{
		interface_options:    sty_deep_merge(base, sls_object(overrides['interface'] or {
			json2.Any(json2.Null{})
		}))
		type_literal_options: sty_deep_merge(base, sls_object(overrides['typeLiteral'] or {
			json2.Any(json2.Null{})
		}))
		last_member:          detection is string && detection == 'last-member'
	}
}

// smds_opts is `{ ...typeOpts.singleline }` or `{ ...typeOpts.multiline }`.
fn smds_opts(type_options map[string]json2.Any, single_line bool) SmdsOpts {
	object := sls_object(type_options[if single_line { 'singleline' } else { 'multiline' }] or {
		json2.Any(json2.Null{})
	})
	delimiter := object['delimiter'] or { json2.Any(json2.Null{}) }
	return SmdsOpts{
		delimiter:    if delimiter is string { delimiter } else { '' }
		require_last: sty_option_bool(object, 'requireLast')
		single_line:  single_line
	}
}

fn (mut c Checker) lint_stylistic_member_delimiter_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	options := smds_options(c.rule_options(stylistic_member_delimiter_style))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		typ := t.typ(node)
		if typ !in [.ts_interface_body, .ts_type_literal] {
			continue
		}
		stats.checked++
		// checkMemberSeparatorStyle.
		members := (if typ == .ts_interface_body {
			t.list(node, .body)
		} else {
			t.list(node, .members)
		}) or { []int{} }
		mut single_line := sty_same_line_offsets(t, t.nodes[node].start, t.nodes[node].end)
		if options.last_member && !single_line && members.len > 0 {
			if sty_same_line_offsets(t, t.nodes[members.last()].end, t.nodes[node].end) {
				single_line = true
			}
		}
		opts := smds_opts(if typ == .ts_interface_body {
			options.interface_options
		} else {
			options.type_literal_options
		}, single_line)
		for index, member in members {
			c.smds_check_last_token(t, tokens, member, opts, index == members.len - 1, mut
				findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// smds_line_length is the length (in UTF-16 units) of the line that holds the offset.
fn smds_line_length(t &estree.EsTree, offset int) int {
	mut end := offset
	for end < t.src.len {
		ch := t.src[end]
		if ch == `\n` || ch == `\r` || (ch == 0xe2 && end + 2 < t.src.len && t.src[end + 1] == 0x80
			&& (t.src[end + 2] == 0xa8 || t.src[end + 2] == 0xa9)) {
			break
		}
		end++
	}
	_, column := t.line_column(end)
	return column
}

// smds_check_last_token ports checkLastToken.
fn (c &Checker) smds_check_last_token(t &estree.EsTree, tokens &SourceTokens, member int, opts SmdsOpts, is_last bool, mut findings []Finding) {
	get_option := fn [opts, is_last] (typ string) bool {
		if is_last && !(opts.require_last or { false }) {
			return typ == 'none'
		}
		return opts.delimiter == typ
	}
	last_token := un_last_token(t, tokens, member) or { return }
	comments := tokens.comments_after(last_token.end)
	opts_semi := get_option('semi')
	opts_comma := get_option('comma')
	opts_none := get_option('none')
	mut message_id := ''
	mut missing_delimiter := false
	value := c.token_text(last_token)
	if value == ';' {
		if opts_comma {
			message_id = 'expectedComma'
		} else if opts_none {
			missing_delimiter = true
			message_id = 'unexpectedSemi'
		}
	} else if value == ',' {
		if opts_semi {
			message_id = 'expectedSemi'
		} else if opts_none {
			missing_delimiter = true
			message_id = 'unexpectedComma'
		}
	} else if opts_semi {
		missing_delimiter = true
		message_id = 'expectedSemi'
	} else if opts_comma {
		missing_delimiter = true
		message_id = 'expectedComma'
	}
	if message_id == '' {
		return
	}
	// makeFixFunction.
	line_length := smds_line_length(t, last_token.start)
	_, start_column := t.line_column(last_token.start)
	is_last_token_end_of_line := start_column == line_length - 1
	mut is_comments_end_of_line := false
	if comments.len > 0 {
		comment := comments.last()
		comment_line, comment_column := t.line_column(comment.end)
		token_line, _ := t.line_column(last_token.end)
		is_comments_end_of_line = comment_line > token_line || comment_column == line_length
	}
	has_fix := !(opts_none && !is_last_token_end_of_line && !is_comments_end_of_line
		&& !opts.single_line)
	delimiter := if opts_semi { ';' } else { ',' }
	fix := if opts_none {
		fix_remove_range(last_token.start, last_token.end)
	} else if missing_delimiter {
		fix_insert_at(last_token.end, delimiter)
	} else {
		fix_replace_range(last_token.start, last_token.end, delimiter)
	}
	findings << Finding{
		stmt:       c.position_range(last_token.end, last_token.end)
		message_id: message_id
		has_fix:    has_fix
		fix:        if has_fix { fix } else { Fix{} }
	}
}
