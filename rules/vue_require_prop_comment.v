module rules

import json2
import time

// Port of the `vue/require-prop-comment` rule of eslint-plugin-vue 10.12.1 (option `type`:
// "JSDoc", the default, "line", "block" or "any"): a prop (of a Vue object or of defineProps)
// whose last comment before it is not of that type.

const vue_require_prop_comment_messages = {
	'requireAnyComment':   'The "{{name}}" property should have a comment.'
	'requireLineComment':  'The "{{name}}" property should have a line comment.'
	'requireBlockComment': 'The "{{name}}" property should have a block comment.'
	'requireJSDocComment': 'The "{{name}}" property should have a JSDoc comment.'
}

fn vue_require_prop_comment_options(options []json2.Any) !string {
	o := option_object(vue_require_prop_comment, options, ['type'])!
	value := o.values['type'] or { return 'JSDoc' }
	return if value is string && value != '' { value } else { 'JSDoc' }
}

fn (mut c Checker) lint_vue_require_prop_comment(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	typ := vue_require_prop_comment_options(c.rule_options(vue_require_prop_comment))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut props := []VueProp{}
	for call in c.vue_macros_named(t, 'defineProps') {
		props << c.vue_define_props(root, t, call, abs_path, false, mut stats)
	}
	for obj in s.objects_of(vue_all_object_types) {
		props << vue_props_from_options(t, obj)
	}
	for prop in props {
		stats.checked++
		if !prop.has_name || prop.name == '' || prop.kind == .infer_type || prop.node < 0 {
			continue
		}
		comments := tokens.comments_before(t.nodes[prop.node].start)
		mut kind := ''
		mut value := ''
		if comments.len > 0 {
			last := comments.last()
			text := c.src[last.start..last.end]
			if last.kind == .line_comment {
				kind = 'Line'
			} else if last.kind == .block_comment {
				kind = 'Block'
				value = text[2..text.len - 2]
			} else {
				kind = 'Shebang'
			}
		}
		is_jsdoc := kind == 'Block' && value.len > 0 && value[0] == `*`
			&& !(value.len > 1 && value[1] == `*`)
		message_id := match typ {
			'block' {
				if kind == 'Block' && !is_jsdoc { '' } else { 'requireBlockComment' }
			}
			'line' {
				if kind == 'Line' { '' } else { 'requireLineComment' }
			}
			'any' {
				if kind != '' { '' } else { 'requireAnyComment' }
			}
			else {
				if is_jsdoc { '' } else { 'requireJSDocComment' }
			}
		}
		if message_id == '' {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, prop.node)
			message_id: message_id
			data:       {
				'name': prop.name
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
