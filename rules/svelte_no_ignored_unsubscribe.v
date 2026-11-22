module rules

// Port of the `svelte/no-ignored-unsubscribe` rule of eslint-plugin-svelte 3.24.1: the property of
// `x.subscribe` called as a statement (the selector "ExpressionStatement > CallExpression >
// MemberExpression.callee[property.name='subscribe']") is reported. It has no conditions: it lints
// every file.

const svniu_messages = {
	'forbidden': 'Ignoring returned value of the subscribe method is forbidden.'
}

fn (mut c Checker) lint_svelte_no_ignored_unsubscribe(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() && !c.src.contains('subscribe') {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	t := e.t
	mut findings := []Finding{}
	for i in e.entered() {
		if t.typ(i) != .member_expression {
			continue
		}
		property := t.node(i, .property) or { continue }
		if t.typ(property) !in [.identifier, .private_identifier]
			|| (t.string_of(property, .name) or { '' }) != 'subscribe' {
			continue
		}
		call := c.svsc_parent(&e, i)
		if call < 0 || t.typ(call) != .call_expression || (t.node(call, .callee) or { -1 }) != i {
			continue
		}
		statement := c.svsc_parent(&e, call)
		if statement < 0 || t.typ(statement) != .expression_statement {
			continue
		}
		findings << c.svsc_report(&e, property, 'forbidden', {})
	}
	return findings
}
