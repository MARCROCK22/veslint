module rules

// Port of the `svelte/no-dom-manipulating` rule of eslint-plugin-svelte 3.24.1: the variables bound
// with `bind:this={x}` to an HTML element (or `<svelte:element>`) and declared in the module or
// global scope are DOM elements; a reference `x.method(…)` (through optional chains) to one of the
// DOM manipulating methods, or an assignment to `x.textContent` and the like, is reported. Only a
// component has such directives.

const svndm_messages = {
	'disallowManipulateDOM': "Don't manipulate the DOM directly. The Svelte runtime can get confused if there is a difference between the actual DOM and the DOM expected by the Svelte runtime."
}

const svndm_methods = ['appendChild', 'insertBefore', 'normalize', 'removeChild', 'replaceChild',
	'after', 'append', 'before', 'insertAdjacentElement', 'insertAdjacentHTML', 'insertAdjacentText',
	'prepend', 'remove', 'replaceChildren', 'replaceWith']

const svndm_properties = ['textContent', 'innerHTML', 'outerHTML', 'innerText', 'outerText']

// svndm_property_name is getPropertyName of eslint-utils for a MemberExpression of the document
// (without a scope: a computed key is a constant string).
fn (c &Checker) svndm_property_name(member int) ?string {
	es := &c.svelte.doc.es
	property := es.node(member, .property)?
	if es.flag(member, .computed) or { false } {
		return c.sv_string_if_constant(property)
	}
	if es.typ(property) == .private_identifier {
		return none
	}
	return es.string_of(property, .name)
}

// svndm_verify is verifyIdentifier.
fn (c &Checker) svndm_verify(id int, mut findings []Finding) {
	es := &c.svelte.doc.es
	member_ref := c.sv_parent(sv_es_ref(id)) or { return }
	if !member_ref.es || es.typ(member_ref.idx) != .member_expression
		|| (es.node(member_ref.idx, .object) or { -1 }) != id {
		return
	}
	member := member_ref.idx
	name := c.svndm_property_name(member) or { return }
	mut target := member
	mut parent := c.sv_parent(sv_es_ref(target)) or { return }
	for parent.es && es.typ(parent.idx) == .chain_expression {
		target = parent.idx
		parent = c.sv_parent(parent) or { return }
	}
	if !parent.es {
		return
	}
	match es.typ(parent.idx) {
		.call_expression {
			if (es.node(parent.idx, .callee) or { -1 }) != target || name !in svndm_methods {
				return
			}
		}
		.assignment_expression {
			if (es.node(parent.idx, .left) or { -1 }) != target || name !in svndm_properties {
				return
			}
		}
		else {
			return
		}
	}
	findings << c.sv_report_es(member, 'disallowManipulateDOM', {})
}

fn (mut c Checker) lint_svelte_no_dom_manipulating(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	info := &doc.scope
	mut variables := []int{}
	for i in c.sv_snodes_of(.directive) {
		n := doc.nodes[i]
		if n.kind != 'Binding' || c.sv_directive_key_name(i) != 'this' || !n.expression.es
			|| n.expression.idx < 0 || doc.es.typ(n.expression.idx) != .identifier {
			continue
		}
		start_tag := n.parent
		if start_tag < 0 || doc.nodes[start_tag].parent < 0 {
			continue
		}
		element := doc.nodes[start_tag].parent
		el := doc.nodes[element]
		if el.typ != .element || !(el.kind == 'html'
			|| (el.kind == 'special' && c.sv_element_name(element) == 'svelte:element')) {
			continue
		}
		v := c.sv_find_variable(n.expression.idx)
		if v < 0 || info.scopes[info.variables[v].scope].typ !in ['module', 'global'] {
			continue
		}
		if v !in variables {
			variables << v
		}
	}
	mut findings := []Finding{}
	for v in variables {
		for r in info.variables[v].references {
			c.svndm_verify(info.references[r].identifier, mut findings)
		}
	}
	return findings
}
