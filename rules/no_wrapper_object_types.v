module rules

import time
import treesitter { position_of }

// Port of the `no-wrapper-object-types` rule of typescript-eslint 8.62.0 (it has no options), with
// its fix.

const nwot_messages = {
	'bannedClassType': 'Prefer using the primitive `{{preferred}}` as a type name, rather than the upper-cased `{{typeName}}`.'
}

const nwot_class_names = ['BigInt', 'Boolean', 'Number', 'Object', 'String', 'Symbol']

fn (mut c Checker) lint_no_wrapper_object_types(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	scopes := c.scope_tree(root)
	// The name of a TSTypeReference, a TSClassImplements or a TSInterfaceHeritage that is one of
	// the global wrapper classes; only a TSTypeReference is fixed.
	for node in c.nodes_of_kind(root, c'type_identifier') {
		type_name := c.text(node)
		if type_name !in nwot_class_names {
			continue
		}
		role := type_name_role(node)
		if role == .other {
			continue
		}
		checked++
		if !is_reference_to_global_function(scopes, node, type_name) {
			continue
		}
		preferred := type_name.to_lower()
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'bannedClassType'
			data:       {
				'preferred': preferred
				'typeName':  type_name
			}
			has_fix:    role == .reference
			fix:        fix_replace(node, preferred)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}
