module rules

import svelte

// Port of the `svelte/no-not-function-handler` rule of eslint-plugin-svelte 3.24.1: the handler of
// an `on:` directive or of an event attribute (`onclick={…}`, the names of src/utils/events.ts) must
// not be an object, an array, a class or a literal value (followed through `const` variables).

const snnfh_messages = {
	'unexpected': 'Unexpected {{phrase}} in event handler.'
}

// snnfh_phrase is PHRASES of the rule: none for an expression that may be a function.
fn (c &Checker) snnfh_phrase(node int) ?string {
	es := &c.svelte.doc.es
	match es.nodes[node].typ {
		.object_expression {
			return 'object'
		}
		.array_expression {
			return 'array'
		}
		.class_expression {
			return 'class'
		}
		.template_literal {
			return 'string value'
		}
		.literal {
			if _ := es.prop(node, .regex) {
				return 'regex value'
			}
			if _ := es.prop(node, .bigint) {
				return 'bigint value'
			}
			value := es.get(node, .value)
			return match value {
				string { 'string value' }
				f64 { 'number value' }
				bool { 'boolean value' }
				else { none }
			}
		}
		else {
			return none
		}
	}
}

// snnfh_verify is the rule's verify.
fn (c &Checker) snnfh_verify(expression svelte.Ref, mut findings []Finding) {
	if expression.idx < 0 || !expression.es {
		return
	}
	mut visited := map[int]bool{}
	root := c.sndsn_root_expression(expression.idx, mut visited)
	phrase := c.snnfh_phrase(root) or { return }
	findings << c.sv_report_es(expression.idx, 'unexpected', {
		'phrase': phrase
	})
}

fn (mut c Checker) lint_svelte_no_not_function_handler(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		if n.typ == .directive && n.kind == 'EventHandler' {
			c.snnfh_verify(n.expression, mut findings)
		} else if n.typ == .attribute && !n.key.es && n.key.idx >= 0
			&& doc.nodes[n.key.idx].typ == .name && doc.nodes[n.key.idx].name in sv_event_names {
			for v in n.values {
				if doc.nodes[v].typ == .mustache_tag {
					c.snnfh_verify(doc.nodes[v].expression, mut findings)
				}
			}
		}
	}
	return findings
}
