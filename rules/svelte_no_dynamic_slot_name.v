module rules

// Port of the `svelte/no-dynamic-slot-name` rule of eslint-plugin-svelte 3.24.1 (deprecated
// upstream): the `name` attribute of a `<slot>` must have a value, and each of its mustache tags is
// reported; the fix writes the tag's constant string (followed through `const` variables) as text.

const sndsn_messages = {
	'unexpected':   '`<slot>` name cannot be dynamic.'
	'requireValue': '`<slot>` name requires a value.'
}

// sndsn_root_expression is findRootExpression: an Identifier of a `const` variable with one
// definition and an initializer is its initializer's root expression.
fn (c &Checker) sndsn_root_expression(node int, mut visited map[int]bool) int {
	es := &c.svelte.doc.es
	if es.nodes[node].typ != .identifier || node in visited {
		return node
	}
	visited[node] = true
	v := c.sv_find_variable(node)
	if v < 0 {
		return node
	}
	variable := c.svelte.doc.scope.variables[v]
	if variable.defs.len != 1 {
		return node
	}
	declarator := c.sv_def_declarator(variable.defs[0].name)
	if declarator < 0 {
		return node
	}
	declaration := es.nodes[declarator].parent
	if declaration < 0 || (es.string_of(declaration, .kind) or { '' }) != 'const' {
		return node
	}
	init := es.node(declarator, .init) or { return node }
	return c.sndsn_root_expression(init, mut visited)
}

fn (mut c Checker) lint_svelte_no_dynamic_slot_name(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	// "SvelteElement[name.name='slot'] > SvelteStartTag.startTag > SvelteAttribute[key.name='name']"
	for attr in c.sv_snodes_of(.attribute) {
		if c.sv_attribute_name(attr) != 'name' {
			continue
		}
		tag := doc.nodes[attr].parent
		if tag < 0 || doc.nodes[tag].typ != .start_tag {
			continue
		}
		element := doc.nodes[tag].parent
		if element < 0 || doc.nodes[element].typ != .element
			|| doc.nodes[element].start_tag != tag
			|| c.sv_ref_name(doc.nodes[element].name_ref) != 'slot' {
			continue
		}
		values := doc.nodes[attr].values
		if values.len == 0 {
			findings << c.sv_report_snode(attr, 'requireValue', {})
			continue
		}
		for v in values {
			vn := doc.nodes[v]
			if vn.typ != .mustache_tag {
				continue
			}
			mut finding := c.sv_report_snode(v, 'unexpected', {})
			if vn.expression.idx >= 0 && vn.expression.es {
				mut visited := map[int]bool{}
				if text := c.sv_string_if_constant(c.sndsn_root_expression(vn.expression.idx, mut
					visited))
				{
					if values.len == 1 {
						if q := c.sv_attribute_value_quote_and_range(attr) {
							finding = Finding{
								...finding
								has_fix: true
								fix:     Fix{
									start: q.start
									end:   q.end
									text:  '"${text}"'
								}
							}
						}
					} else {
						finding = Finding{
							...finding
							has_fix: true
							fix:     Fix{
								start: vn.start
								end:   vn.end
								text:  text
							}
						}
					}
				}
			}
			findings << finding
		}
	}
	return findings
}
