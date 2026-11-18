module rules

import json2
import postcss

// Port of the `svelte/consistent-selector-style` rule of eslint-plugin-svelte 3.24.1: in the
// selectors of the rules of the <style> element, a class, ID or element type selector that could
// be written in a style that comes first in `style` (default type, id, class): an ID when it
// selects at most one element that occurs at most once, a type when it selects all the elements
// of one type (classes and IDs given by expressions count through their literal prefix and
// suffix). :global(...) is skipped unless checkGlobal.

const sccs_messages = {
	'classShouldBeId':   'Selector should select by ID instead of class'
	'classShouldBeType': 'Selector should select by element type instead of class'
	'idShouldBeClass':   'Selector should select by class instead of ID'
	'idShouldBeType':    'Selector should select by element type instead of ID'
	'typeShouldBeClass': 'Selector should select by class instead of element type'
	'typeShouldBeId':    'Selector should select by ID instead of element type'
}

struct SccsOptions {
	check_global bool
	style        []string = ['type', 'id', 'class']
}

fn sccs_options(options []json2.Any) !SccsOptions {
	o := option_object(svelte_consistent_selector_style, options, ['checkGlobal', 'style'])!
	return SccsOptions{
		check_global: if 'checkGlobal' in o.values { o.bool_value('checkGlobal')! } else { false }
		style:        if 'style' in o.values {
			o.string_list('style')!
		} else {
			['type', 'id', 'class']
		}
	}
}

// SccsAffix is an entry of Selections.affixes: the literal prefix and suffix (none: null) of an
// expression, and its element.
struct SccsAffix {
	prefix  ?string
	suffix  ?string
	element int
}

// SccsSelections are the elements a class or an ID selects.
struct SccsSelections {
mut:
	exact     map[string][]int
	affixes   []SccsAffix
	universal bool
}

struct SccsState {
	options SccsOptions
	ctx     &SvstContext
mut:
	class       SccsSelections
	id          SccsSelections
	typ         map[string][]int
	whitelisted []string
	findings    []Finding
}

fn (mut c Checker) lint_svelte_consistent_selector_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := sccs_options(c.rule_options(svelte_consistent_selector_style))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	ctx := c.svst_style_context(abs_path)
	mut st := SccsState{
		options: options
		ctx:     &ctx
	}
	for el in c.sv_snodes_of(.element) {
		n := doc.nodes[el]
		if n.kind != 'html' || n.start_tag < 0 {
			continue
		}
		st.typ[c.sv_ref_name(n.name_ref)] << el
		for a in doc.nodes[n.start_tag].attributes {
			an := doc.nodes[a]
			if an.typ == .directive && an.kind == 'Class' {
				st.whitelisted << c.sv_directive_key_name(a)
			}
			for class_name in c.svaf_classes_in_attribute(a) {
				st.class.exact[class_name] << el
			}
			if an.typ != .attribute {
				continue
			}
			name := c.sv_attribute_name(a)
			for v in an.values {
				vn := doc.nodes[v]
				if name == 'class' && vn.typ == .mustache_tag {
					sccs_add_expression(mut st.class, c, vn.expression.idx, el)
				}
				if name == 'id' {
					if vn.typ == .literal {
						st.id.exact[vn.value] << el
					} else if vn.typ == .mustache_tag {
						sccs_add_expression(mut st.id, c, vn.expression.idx, el)
					}
				}
			}
		}
	}
	if ctx.status != .success {
		return []
	}
	c.sccs_check_postcss_node(mut st, 0)
	return st.findings
}

fn sccs_add_expression(mut s SccsSelections, c &Checker, expression int, el int) {
	prefix := c.svaf_prefix_literal(expression)
	suffix := c.svaf_suffix_literal(expression)
	if prefix == none && suffix == none {
		s.universal = true
	} else {
		s.affixes << SccsAffix{
			prefix:  prefix
			suffix:  suffix
			element: el
		}
	}
}

fn (c &Checker) sccs_check_postcss_node(mut st SccsState, i int) {
	n := st.ctx.root.nodes[i]
	if n.typ == .rule {
		// postcss-selector-parser throws on a selector it cannot parse (the rule crashes in
		// ESLint): such a rule is skipped.
		if sel := postcss.parse_selector(n.selector) {
			c.sccs_check_selector(mut st, i, &sel, 0)
		}
	}
	if (n.typ == .root || (n.typ == .rule && (n.selector != ':global' || st.options.check_global))
		|| n.typ == .atrule) && n.has_nodes {
		for k in n.nodes {
			c.sccs_check_postcss_node(mut st, k)
		}
	}
}

fn (c &Checker) sccs_check_selector(mut st SccsState, rule int, sel &postcss.SelectorRoot, i int) {
	n := sel.nodes[i]
	match n.typ {
		.class { c.sccs_check_class(mut st, rule, n) }
		.id { c.sccs_check_id(mut st, rule, n) }
		.tag { c.sccs_check_type(mut st, rule, n) }
		else {}
	}
	if (n.typ == .pseudo && (n.value != ':global' || st.options.check_global)) || n.typ == .root
		|| n.typ == .selector {
		for k in n.nodes {
			c.sccs_check_selector(mut st, rule, sel, k)
		}
	}
}

// sccs_match_selection is matchSelection: the elements a key selects, exactly or through an
// affix.
fn sccs_match_selection(s &SccsSelections, key string) [][]int {
	mut out := [][]int{}
	for el in s.exact[key] or { []int{} } {
		out << [el, 1]
	}
	for a in s.affixes {
		prefix_ok := if p := a.prefix { key.starts_with(p) } else { true }
		suffix_ok := if p := a.suffix { key.ends_with(p) } else { true }
		if prefix_ok && suffix_ok {
			out << [a.element, 0]
		}
	}
	return out
}

fn (c &Checker) sccs_can_use_id(selection []int) bool {
	return selection.len == 0
		|| (selection.len == 1 && c.svaf_occurrence_count(selection[0]) != .zero_to_inf)
}

fn (c &Checker) sccs_can_use_type(selection [][]int, types_map map[string][]int) bool {
	mut types := []string{}
	for s in selection {
		name := c.sv_ref_name(c.svelte.doc.nodes[s[0]].name_ref)
		if name !in types {
			types << name
		}
	}
	if types.len > 1 {
		return false
	}
	if types.len < 1 {
		return true
	}
	if selection.any(it[1] == 0 && c.svaf_occurrence_count(it[0]) == .zero_to_inf) {
		return false
	}
	type_selection := types_map[types[0]] or { return false }
	elements := selection.map(it[0])
	return type_selection.len == elements.len && type_selection.all(it in elements)
}

fn (c &Checker) sccs_report(mut st SccsState, rule int, n &postcss.SelNode, message_id string) {
	st.findings << c.svst_selector_report(st.ctx, rule, n, message_id)
}

fn (c &Checker) sccs_check_class(mut st SccsState, rule int, n postcss.SelNode) {
	if st.class.universal || n.value in st.whitelisted {
		return
	}
	selection := sccs_match_selection(&st.class, n.value)
	for style in st.options.style {
		if style == 'class' {
			return
		}
		if style == 'id' && c.sccs_can_use_id(selection.map(it[0])) {
			c.sccs_report(mut st, rule, &n, 'classShouldBeId')
			return
		}
		if style == 'type' && c.sccs_can_use_type(selection, st.typ) {
			c.sccs_report(mut st, rule, &n, 'classShouldBeType')
			return
		}
	}
}

fn (c &Checker) sccs_check_id(mut st SccsState, rule int, n postcss.SelNode) {
	if st.id.universal {
		return
	}
	selection := sccs_match_selection(&st.id, n.value)
	for style in st.options.style {
		if style == 'class' {
			c.sccs_report(mut st, rule, &n, 'idShouldBeClass')
			return
		}
		if style == 'id' {
			return
		}
		if style == 'type' && c.sccs_can_use_type(selection, st.typ) {
			c.sccs_report(mut st, rule, &n, 'idShouldBeType')
			return
		}
	}
}

fn (c &Checker) sccs_check_type(mut st SccsState, rule int, n postcss.SelNode) {
	selection := st.typ[n.value] or { []int{} }
	for style in st.options.style {
		if style == 'class' {
			c.sccs_report(mut st, rule, &n, 'typeShouldBeClass')
			return
		}
		if style == 'id' && c.sccs_can_use_id(selection) {
			c.sccs_report(mut st, rule, &n, 'typeShouldBeId')
			return
		}
		if style == 'type' {
			return
		}
	}
}
