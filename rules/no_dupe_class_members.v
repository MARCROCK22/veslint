module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-dupe-class-members` rule of typescript-eslint 8.62.0 (it has no options), which
// extends the rule of ESLint 10.6.0 with the same name: computed keys are skipped.

const ndcm_messages = {
	'unexpected': "Duplicate name '{{name}}'."
}

// NdcmState is what a class already declared with a name, static or not: a member that is not an
// accessor, a getter or a setter.
struct NdcmState {
mut:
	init bool
	get  bool
	set  bool
}

fn (mut c Checker) lint_no_dupe_class_members(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for body in c.nodes_of_kind(root, c'class_body') {
		mut states := map[string]NdcmState{}
		for member in cm_members(body) {
			// `MethodDefinition, PropertyDefinition`, without a TSEmptyBodyFunctionExpression (an
			// overload, or a method of a declared class) and with a key that is not computed.
			member_type := cm_type(member)
			if member_type !in ['MethodDefinition', 'PropertyDefinition']
				|| node_kind(member) == 'method_signature' {
				continue
			}
			key := node_field(member, 'name') or { continue }
			if node_kind(key) == 'computed_property_name' {
				continue
			}
			// getStaticPropertyName: null for a private name.
			name := c.core_static_property_name(key) or { continue }
			kind := if member_type == 'MethodDefinition' {
				c.cm_method_kind(member)
			} else {
				'field'
			}
			if kind == 'constructor' {
				continue
			}
			checked++
			state_key := if cm_is_static(member) { 'static ${name}' } else { 'nonStatic ${name}' }
			mut state := states[state_key] or { NdcmState{} }
			is_duplicate := match kind {
				'get' { state.init || state.get }
				'set' { state.init || state.set }
				else { state.init || state.get || state.set }
			}
			match kind {
				'get' { state.get = true }
				'set' { state.set = true }
				else { state.init = true }
			}
			states[state_key] = state
			if is_duplicate {
				findings << Finding{
					stmt:       position_of(key)
					message_id: 'unexpected'
					data:       {
						'name': name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
