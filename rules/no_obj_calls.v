module rules

import time
import treesitter { node_field, node_kind, position_of }

// Port of the `no-obj-calls` rule of ESLint 10.6.0 (it has no options).

const noc2_messages = {
	'unexpectedCall':    "'{{name}}' is not a function."
	'unexpectedRefCall': "'{{name}}' is reference to '{{ref}}', which is not a function."
}

fn (mut c Checker) lint_no_obj_calls(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut trace := map[string]EsTrace{}
	for name in ['Atomics', 'JSON', 'Math', 'Reflect', 'Intl', 'Temporal'] {
		trace[name] = EsTrace{
			call:      true
			construct: true
		}
	}
	for traced in c.es_global_references(root, trace) {
		stats.checked++
		callee := unwrap_parens(node_field(traced.node, if node_kind(traced.node) == 'new_expression' {
			'constructor'
		} else {
			'function'
		}) or { continue })
		// getReportNodeName: a member's property, an identifier's name, `undefined` otherwise.
		name := if node_kind(callee) in ['member_expression', 'subscript_expression'] {
			c.es_static_property_name(callee) or { 'null' }
		} else if node_kind(callee) in ['identifier', 'undefined'] {
			c.text(callee)
		} else {
			'undefined'
		}
		ref := traced.path[0]
		findings << Finding{
			stmt:       position_of(traced.node)
			message_id: if name == ref { 'unexpectedCall' } else { 'unexpectedRefCall' }
			data:       {
				'name': name
				'ref':  ref
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
