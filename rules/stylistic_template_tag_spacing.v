module rules

import estree
import time
import x.json2

// Port of the `@stylistic/template-tag-spacing` rule of @stylistic/eslint-plugin 6.0.1, with its
// option (`"always"` or `"never"`, the default) and its fixes.

const stts_messages = {
	'unexpected': 'Unexpected space between template tag and template literal.'
	'missing':    'Missing space between template tag and template literal.'
}

fn stts_options(given []json2.Any) !bool {
	options := sty_options(given, [json2.Any('never')])
	return sty_option_string(options, 0, '') != 'always'
}

fn (mut c Checker) lint_stylistic_template_tag_spacing(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	never := stts_options(c.rule_options(stylistic_template_tag_spacing))!
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	// In the order of ESLint's traversal: reports that start at the same place keep it.
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		if t.typ(node) != .tagged_template_expression {
			continue
		}
		stats.checked++
		c.stts_check(t, tokens, node, never, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// stts_check ports checkSpacing.
fn (c &Checker) stts_check(t &estree.EsTree, tokens &SourceTokens, node int, never bool, mut findings []Finding) {
	quasi := t.node(node, .quasi) or { return }
	quasi_start := t.nodes[quasi].start
	tag_token := tokens.before(quasi_start, false) or { return }
	literal_token := un_first_token(t, tokens, quasi, 0) or { return }
	has_whitespace := tokens.is_space_between(tag_token.end, literal_token.start)
	if never && has_whitespace {
		comments := tokens.comments_before(quasi_start)
		// No fix when a line comment follows the tag.
		has_line_comment := comments.any(it.kind == .line_comment)
		mut text := ''
		for comment in comments {
			text += c.token_text(comment)
		}
		findings << Finding{
			stmt:       c.position_range(tag_token.end, literal_token.start)
			message_id: 'unexpected'
			has_fix:    !has_line_comment
			fix:        if has_line_comment {
				Fix{}
			} else {
				fix_replace_range(tag_token.end, literal_token.start, text)
			}
		}
	} else if !never && !has_whitespace {
		findings << Finding{
			stmt:       c.position_range(t.nodes[node].start, literal_token.start)
			message_id: 'missing'
			has_fix:    true
			fix:        fix_replace_range(tag_token.end, tag_token.end, ' ')
		}
	}
}
