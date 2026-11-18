module rules

// Port of the `svelte/no-object-in-text-mustaches` rule of eslint-plugin-svelte 3.24.1: a
// mustache tag whose expression is an object, an array, a function or a class (it would print
// `[object Object]` or the like), but the one value of an attribute.

const snoitm_messages = {
	'unexpected': 'Unexpected {{phrase}} in text mustache interpolation.'
}

const snoitm_phrases = {
	'ObjectExpression':        'object'
	'ArrayExpression':         'array'
	'ArrowFunctionExpression': 'function'
	'FunctionExpression':      'function'
	'ClassExpression':         'class'
}

fn (mut c Checker) lint_svelte_no_object_in_text_mustaches(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.mustache_tag) {
		n := doc.nodes[i]
		if n.expression.idx < 0 {
			continue
		}
		phrase := snoitm_phrases[c.sv_ref_type(n.expression)] or { continue }
		if n.parent >= 0 && doc.nodes[n.parent].typ == .attribute
			&& doc.nodes[n.parent].values.len == 1 {
			continue
		}
		findings << c.sv_report_snode(i, 'unexpected', {
			'phrase': phrase
		})
	}
	return findings
}
