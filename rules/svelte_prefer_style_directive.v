module rules

// Port of the `svelte/prefer-style-directive` rule of eslint-plugin-svelte 3.24.1: in the `style`
// attribute of an HTML element, a declaration without `!important` and without interpolations in
// its property, and an interpolation `{c ? 'prop: value' : ''}` (one branch empty, the other one
// declaration), can be `style:` directives (unless the element has one for that property). The fix
// writes the directive and takes the declaration out of the attribute (or replaces it).

const spsd_messages = {
	'unexpected': 'Can use style directives instead.'
}

fn (mut c Checker) lint_svelte_prefer_style_directive(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for attr in c.sv_snodes_of(.attribute) {
		tag := doc.nodes[attr].parent
		if tag < 0 || doc.nodes[tag].typ != .start_tag || doc.nodes[tag].parent < 0
			|| !c.sv_is_html_element_like(doc.nodes[tag].parent)
			|| c.sv_attribute_name(attr) != 'style' {
			continue
		}
		style := c.svst_parse_attribute(attr) or { continue }
		for k, child in style.nodes {
			if child.kind == .decl {
				if f := c.spsd_declaration(attr, style, k) {
					findings << f
				}
			} else if child.kind == .inline {
				if f := c.spsd_inline(attr, style, k) {
					findings << f
				}
			}
		}
	}
	return findings
}

// spsd_has_directive tells whether the start tag of the attribute has a `style:` directive for
// the property.
fn (c &Checker) spsd_has_directive(attr int, prop string) bool {
	doc := c.svelte.doc
	for a in doc.nodes[doc.nodes[attr].parent].attributes {
		if doc.nodes[a].typ == .style_directive && c.sv_directive_key_name(a) == prop {
			return true
		}
	}
	return false
}

fn (c &Checker) spsd_declaration(attr int, style SvstRoot, k int) ?Finding {
	decl := style.nodes[k]
	if decl.important || decl.unknown_interps.len > 0 || decl.prop_interps.len > 0 {
		return none
	}
	if c.spsd_has_directive(attr, decl.prop) {
		return none
	}
	directive := 'style:${decl.prop}="${c.sv_text(decl.value_start, decl.value_end)}"'
	return c.spsd_report(c.sv_report_text(decl.start, decl.end, 'unexpected', {}), attr,
		style, k, directive)
}

fn (c &Checker) spsd_inline(attr int, style SvstRoot, k int) ?Finding {
	inline := style.nodes[k]
	doc := c.svelte.doc
	es := &doc.es
	mustache := inline.interp.r
	if mustache.es || doc.nodes[mustache.idx].typ != .mustache_tag {
		return none
	}
	node := doc.nodes[mustache.idx].expression
	if !node.es || node.idx < 0 || es.nodes[node.idx].typ != .conditional_expression {
		return none
	}
	test := es.node(node.idx, .test)?
	consequent := es.node(node.idx, .consequent)?
	alternate := es.node(node.idx, .alternate)?
	if !c.svst_is_string_literal(consequent) || !c.svst_is_string_literal(alternate) {
		return none
	}
	consequent_value := es.get(consequent, .value) as string
	alternate_value := es.get(alternate, .value) as string
	if consequent_value != '' && alternate_value != '' {
		return none
	}
	positive := alternate_value == ''
	inline_root := c.svst_inline_style(sv_es_ref(if positive { consequent } else { alternate }))?
	if inline_root.nodes.len != 1 || inline_root.nodes[0].kind != .decl {
		return none
	}
	decl := inline_root.nodes[0]
	if c.spsd_has_directive(attr, decl.prop) {
		return none
	}
	cn := es.nodes[consequent]
	an := es.nodes[alternate]
	src := doc.src
	mut value := c.sv_text(es.nodes[test].start, cn.start)
	if positive {
		value += src[cn.start..cn.start + 1] + decl.value + src[cn.end - 1..cn.end]
	} else {
		value += 'null'
	}
	value += c.sv_text(cn.end, an.start)
	if positive {
		value += 'null'
	} else {
		value += src[an.start..an.start + 1] + decl.value + src[an.end - 1..an.end]
	}
	directive := 'style:${decl.prop}={${value}}'
	return c.spsd_report(c.sv_report_es(node.idx, 'unexpected', {}), attr, style, k, directive)
}

// spsd_report adds the fix: the attribute replaced by the directive when the node is all of it,
// else the node removed and the directive written before the attribute (for its first node) or
// after it.
fn (c &Checker) spsd_report(finding Finding, attr int, style SvstRoot, k int, directive string) ?Finding {
	a := c.svelte.doc.nodes[attr]
	mut fixes := []Fix{}
	if style.nodes.len == 1 {
		fixes << Fix{
			start: a.start
			end:   a.end
			text:  directive
		}
	} else {
		node := style.nodes[k]
		fixes << if k + 1 < style.nodes.len {
			Fix{
				start: node.start
				end:   style.nodes[k + 1].start
			}
		} else if k > 0 {
			Fix{
				start: style.nodes[k - 1].end
				end:   node.end
			}
		} else {
			Fix{
				start: node.start
				end:   node.end
			}
		}
		fixes << if k == 0 {
			Fix{
				start: a.start
				end:   a.start
				text:  '${directive} '
			}
		} else {
			Fix{
				start: a.end
				end:   a.end
				text:  ' ${directive}'
			}
		}
	}
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	return Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}
