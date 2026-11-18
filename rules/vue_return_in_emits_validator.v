module rules

import estree
import math
import time

// Port of the `vue/return-in-emits-validator` rule of eslint-plugin-vue 10.12.1 (no options): a
// validator function of an object `emits` (of a Vue object or of defineEmits) that cannot return
// a truthy value.

const vue_return_in_emits_validator_messages = {
	'expectedTrue':    'Expected to return a true value in "{{name}}" emits validator.'
	'expectedBoolean': 'Expected to return a boolean value in "{{name}}" emits validator.'
}

// vriev_is_falsy ports isFalsy: a falsy literal, `undefined` or `NaN`.
fn vriev_is_falsy(t &estree.EsTree, node int) bool {
	if t.typ(node) == .literal {
		value := t.get(node, .value)
		match value {
			estree.BigIntValue {
				return value.digits == '0'
			}
			bool {
				if !value {
					return true
				}
			}
			f64 {
				if value == 0 || math.is_nan(value) {
					return true
				}
			}
			string {
				if value == '' {
					return true
				}
			}
			estree.Null {
				return true
			}
			else {}
		}
	}
	if t.typ(node) == .identifier {
		name := t.string_of(node, .name) or { '' }
		return name == 'undefined' || name == 'NaN'
	}
	return false
}

// VrievValidator is an emits validator, with the node after whose enter the rule knows it (its
// function's exit must come later).
struct VrievValidator {
	function int
	name     string
	known_at int
}

fn (mut c Checker) lint_vue_return_in_emits_validator(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	mut validators := []VrievValidator{}
	for call in c.vue_macros_named(t, 'defineEmits') {
		vriev_collect(t, c.vue_define_emits(root, t, call, abs_path, false, mut stats), t.nodes[call].start, mut validators)
	}
	for obj in s.objects_of(vue_all_object_types) {
		vriev_collect(t, vue_emits_from_options(t, obj), t.nodes[obj].start, mut validators)
	}
	for v in validators {
		stats.checked++
		f := v.function
		// The `:function:exit` of the validator comes after the rule knows it.
		if t.nodes[f].end <= v.known_at {
			continue
		}
		mut has_return_value := false
		mut possible_true := false
		body := t.node(f, .body) or { -1 }
		if t.typ(f) == .arrow_function_expression && body >= 0 && t.typ(body) != .block_statement {
			has_return_value = true
			if !vriev_is_falsy(t, body) {
				possible_true = true
			}
		}
		for r in vriev_own_returns(t, f) {
			argument := t.node(r, .argument) or { continue }
			has_return_value = true
			if !vriev_is_falsy(t, argument) {
				possible_true = true
			}
		}
		if possible_true {
			continue
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, f)
			message_id: if has_return_value { 'expectedTrue' } else { 'expectedBoolean' }
			data:       {
				'name': if v.name != '' { v.name } else { 'Unknown' }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn vriev_collect(t &estree.EsTree, emits []VueProp, known_at int, mut out []VrievValidator) {
	for emit in emits {
		if emit.kind != .object || emit.value < 0
			|| t.typ(emit.value) !in [.function_expression, .arrow_function_expression] {
			continue
		}
		if out.any(it.function == emit.value) {
			continue
		}
		out << VrievValidator{
			function: emit.value
			name:     if emit.has_name { emit.name } else { '' }
			known_at: known_at
		}
	}
}

// vriev_own_returns are the return statements whose innermost function is `function`.
fn vriev_own_returns(t &estree.EsTree, function int) []int {
	mut out := []int{}
	start := t.nodes[function].start
	end := t.nodes[function].end
	for i in 0 .. t.nodes.len {
		if t.typ(i) != .return_statement || t.nodes[i].start < start || t.nodes[i].end > end {
			continue
		}
		mut p := t.nodes[i].parent
		for p >= 0 && t.typ(p) !in [.function_expression, .function_declaration,
			.arrow_function_expression] {
			p = t.nodes[p].parent
		}
		if p == function {
			out << i
		}
	}
	return out
}
