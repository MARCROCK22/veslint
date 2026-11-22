module rules

import time
import treesitter { node_kind, node_parent, position_of }

// Port of the `no-proto` rule of ESLint 10.15.0 (it has no options).

const nprt_messages = {
	'unexpectedProto': "The '__proto__' property is deprecated."
}

fn (mut c Checker) lint_no_proto(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['member_expression', 'subscript_expression'], []) {
		stats.checked++
		if in_type_name(node) {
			continue
		}
		if (c.es_static_property_name(node) or { continue }) == '__proto__' {
			findings << Finding{
				stmt:       position_of(node)
				message_id: 'unexpectedProto'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// in_type_name: a member access of a type name, which tree-sitter's grammar reads as member
// accesses and typescript-estree as no MemberExpression: the qualified name of `typeof a.b` (a
// TSQualifiedName in a TSTypeQuery) and the names after `import('…')` in a type (`typeof
// import('x').a.b`, the qualifier of a TSImportType). ESLint's rules on MemberExpression skip them.
fn in_type_name(n C.vt_node) bool {
	mut node := n
	for _ in 0 .. max_expression_depth {
		parent := node_parent(node) or { return false }
		match node_kind(parent) {
			// `typeof a.b<T>`: the type arguments of the TSTypeQuery.
			'member_expression', 'instantiation_expression' {
				node = parent
			}
			'type_query', 'import_type' {
				return true
			}
			else {
				return false
			}
		}
	}
	return false
}
