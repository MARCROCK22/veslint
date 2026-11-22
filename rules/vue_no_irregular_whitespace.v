module rules

import estree
import json2
import time

// Port of the `vue/no-irregular-whitespace` rule of eslint-plugin-vue 10.12.1 (options
// `skipComments`, `skipStrings` (on by default), `skipTemplates`, `skipRegExps`,
// `skipHTMLAttributeValues`, `skipHTMLTextContents`): ESLint core's no-irregular-whitespace on the
// script and the template of a .vue file (and on a .ts file): the runs of irregular white space
// and the irregular line terminators within the Program's range or the template's, but those in
// the strings, template elements, regular expressions, comments, attribute values or texts the
// options skip. The irregular characters are those of the core rule (rules/no_irregular_whitespace.v).

const vnirw_messages = {
	'disallow': 'Irregular whitespace not allowed.'
}

struct VnirwOptions {
	skip_comments         bool
	skip_strings          bool = true
	skip_regexps          bool
	skip_templates        bool
	skip_attribute_values bool
	skip_text_contents    bool
}

fn vnirw_options(options []json2.Any) !VnirwOptions {
	o := option_object(vue_no_irregular_whitespace, options, ['skipComments', 'skipStrings',
		'skipTemplates', 'skipRegExps', 'skipHTMLAttributeValues', 'skipHTMLTextContents'])!
	// `options.skipStrings !== false`.
	mut skip_strings := true
	if value := o.values['skipStrings'] {
		if value is bool && !value {
			skip_strings = false
		}
	}
	return VnirwOptions{
		skip_comments:         o.bool_value('skipComments')!
		skip_strings:          skip_strings
		skip_regexps:          o.bool_value('skipRegExps')!
		skip_templates:        o.bool_value('skipTemplates')!
		skip_attribute_values: o.bool_value('skipHTMLAttributeValues')!
		skip_text_contents:    o.bool_value('skipHTMLTextContents')!
	}
}

// vnirw_skip_es records the ranges of the Literal and TemplateElement nodes of an EsTree whose
// irregular white space the options allow.
fn (c &Checker) vnirw_skip_es(t &estree.EsTree, node int, opts VnirwOptions, mut allowed [][]int) {
	n := t.nodes[node]
	match t.typ(node) {
		.literal {
			check_strings := opts.skip_strings && t.get(node, .value) is string
			mut has_regex := false
			if _ := t.prop(node, .regex) {
				has_regex = true
			}
			check_regexps := opts.skip_regexps && has_regex
			if (check_strings || check_regexps) && niw_has_irregular(c.src[n.start..n.end]) {
				allowed << [n.start, n.end]
			}
		}
		.template_element {
			if opts.skip_templates {
				v := t.get(node, .value)
				if v is estree.TemplateValue && niw_has_irregular(v.raw) {
					allowed << [n.start, n.end]
				}
			}
		}
		else {}
	}
}

fn (mut c Checker) lint_vue_no_irregular_whitespace(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	stats.checked++
	mut findings := []Finding{}
	if !niw_has_irregular(c.src) {
		stats.eval_ms += ms(sw.elapsed())
		return findings
	}
	opts := vnirw_options(c.rule_options(vue_no_irregular_whitespace))!
	// The runs of irregular white space, then the irregular line terminators.
	mut errors := [][]int{}
	mut i := 0
	mut in_run := false
	for i < c.src.len {
		r, size := niw_rune_at(c.src, i)
		if r in niw_spaces {
			if !in_run {
				errors << [i, i + size]
				in_run = true
			} else {
				errors[errors.len - 1][1] = i + size
			}
		} else {
			in_run = false
		}
		i += size
	}
	i = 0
	for i < c.src.len {
		r, size := niw_rune_at(c.src, i)
		if r in niw_terminators {
			errors << [i, i + size]
		}
		i += size
	}
	// The ranges where the options allow it.
	mut allowed := [][]int{}
	if t := c.es_tree(root, abs_path) {
		for node in 0 .. t.nodes.len {
			c.vnirw_skip_es(t, node, opts, mut allowed)
		}
	}
	vue_file := c.is_vue()
	if c.vue_has_template() {
		for step in c.vue_template_steps() {
			if step.leave {
				continue
			}
			n := step.node
			if n.kind == .estree {
				c.vnirw_skip_es(&c.vue.doc.snippets[n.snippet].es, n.es, opts, mut allowed)
				continue
			}
			if n.kind != .vnode {
				continue
			}
			node := &c.vue.doc.nodes[n.v]
			if node.typ == .v_literal && opts.skip_attribute_values && node.parent >= 0 {
				attr := &c.vue.doc.nodes[node.parent]
				if attr.typ == .v_attribute && !attr.directive
					&& niw_has_irregular(c.vue_vnode_text(n.v)) {
					allowed << [node.start, node.end]
				}
			}
			if node.typ == .v_text && opts.skip_text_contents
				&& niw_has_irregular(c.vue_vnode_text(n.v)) {
				allowed << [node.start, node.end]
			}
		}
	}
	if opts.skip_comments {
		for comment in c.source_tokens(root).comments {
			text := c.src[comment.start..comment.end]
			value := if text.starts_with('//') {
				text[2..]
			} else if text.len >= 4 {
				text[2..text.len - 2]
			} else {
				''
			}
			if niw_has_irregular(value) {
				allowed << [comment.start, comment.end]
			}
		}
		if c.vue_has_template() {
			for comment in c.vue.doc.comments {
				if niw_has_irregular(comment.value) {
					allowed << [comment.start, comment.end]
				}
			}
		}
	}
	// The Program's range and the template's.
	mut ranges := [][]int{}
	if vue_file {
		ranges << [c.vue.doc.script.program_start, c.vue.doc.script.program_end]
		if c.vue_has_template() {
			body := c.vue.doc.nodes[c.vue.doc.template_body]
			ranges << [body.start, body.end]
		}
	} else {
		ranges << [0, c.src.len]
	}
	for error in errors {
		offset := error[0]
		if allowed.any(offset >= it[0] && offset < it[1]) {
			continue
		}
		if !ranges.any(it[0] <= offset && offset < it[1]) {
			continue
		}
		findings << Finding{
			stmt:       c.position_range(offset, error[1])
			message_id: 'disallow'
			text_loc:   true
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
