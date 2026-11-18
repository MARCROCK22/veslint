module rules

import estree
import time

// Port of the `vue/require-emit-validator` rule of eslint-plugin-vue 10.12.1 (no options): an emit
// of the options or of `defineEmits` without a validator function (an item of an array, or a
// property whose value is not a function or an identifier), with a suggestion for a `null` one.

const vue_require_emit_validator_messages = {
	'missing':         'Emit "{{name}}" should define at least its validator function.'
	'skipped':         'Emit "{{name}}" should not skip validation, or you may define a validator function with no parameters.'
	'emptyValidation': 'Replace with a validator function with no parameters.'
}

fn (mut c Checker) lint_vue_require_emit_validator(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut emits := []VueProp{}
	for obj in s.objects_of(vue_all_object_types) {
		emits << vue_emits_from_options(t, obj)
	}
	for call in c.vue_macros_named(t, 'defineEmits') {
		emits << c.vue_define_emits(root, t, call, abs_path, false, mut stats)
	}
	for emit in emits {
		stats.checked++
		finding := c.vue_emit_validator_finding(t, emit) or { continue }
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) vue_emit_validator_finding(t &estree.EsTree, emit VueProp) ?Finding {
	mut value := -1
	if emit.kind == .object {
		value = emit.value
		if t.typ(value) in [.arrow_function_expression, .function_expression, .identifier] {
			return none
		}
	} else if emit.kind != .array {
		return none
	}
	name := if emit.has_name && emit.name != '' {
		emit.name
	} else if emit.node >= 0 && t.typ(emit.node) == .identifier {
		t.string_of(emit.node, .name) or { 'Unknown emit' }
	} else {
		'Unknown emit'
	}
	if value >= 0 && t.typ(value) == .literal && t.get(value, .value) is estree.Null {
		_, suggestion := c.suggestion('emptyValidation', {}, [
			fix_replace_range(t.nodes[value].start, t.nodes[value].end, '() => true'),
		]) or { return none }
		return Finding{
			stmt:        c.es_tree_position(t, emit.node)
			message_id:  'skipped'
			data:        {
				'name': name
			}
			suggestions: [suggestion]
		}
	}
	return Finding{
		stmt:       c.es_tree_position(t, emit.node)
		message_id: 'missing'
		data:       {
			'name': name
		}
	}
}
