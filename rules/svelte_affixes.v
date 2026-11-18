module rules

import estree
import postcss

// eslint-plugin-svelte 3.24.1's utils/expression-affixes.ts (the literal prefix and suffix of an
// expression), utils/element-occurences.ts and findClassesInAttribute of utils/ast-utils.ts
// (prefix `svaf_`), for consistent-selector-style and no-unused-class-name.

// SvafFinder is FindVariableContext: findVariable that gives null for an identifier it saw
// already (a variable whose initializer leads back to it).
struct SvafFinder {
mut:
	visited map[int]bool
}

fn (c &Checker) svaf_find_variable(mut f SvafFinder, id int) int {
	if id in f.visited {
		return -1
	}
	f.visited[id] = true
	return c.sv_find_variable(id)
}

// svaf_init is the initializer of the one definition of a variable when its name is the id of a
// VariableDeclarator, -1 otherwise.
fn (c &Checker) svaf_init(variable int) int {
	doc := c.svelte.doc
	if variable < 0 {
		return -1
	}
	v := doc.scope.variables[variable]
	if v.defs.len != 1 {
		return -1
	}
	parent := doc.es.nodes[v.defs[0].name].parent
	if parent < 0 || doc.es.nodes[parent].typ != .variable_declarator {
		return -1
	}
	return doc.es.node(parent, .init) or { -1 }
}

// svaf_template_parts are the quasis and expressions of a template literal in source order.
fn (c &Checker) svaf_template_parts(node int) []int {
	es := &c.svelte.doc.es
	mut parts := es.list(node, .quasis) or { []int{} }
	parts << es.list(node, .expressions) or { []int{} }
	parts.sort_with_compare(fn [es] (a &int, b &int) int {
		return if es.nodes[*a].start < es.nodes[*b].start { -1 } else { 1 }
	})
	return parts
}

fn (c &Checker) svaf_raw(quasi int) string {
	value := c.svelte.doc.es.get(quasi, .value)
	if value is estree.TemplateValue {
		return value.raw
	}
	return ''
}

// svaf_prefix_literal is extractExpressionPrefixLiteral of an ESTree node.
fn (c &Checker) svaf_prefix_literal(node int) ?string {
	mut f := SvafFinder{}
	return c.svaf_affix(mut f, node, true)
}

// svaf_suffix_literal is extractExpressionSuffixLiteral of an ESTree node.
fn (c &Checker) svaf_suffix_literal(node int) ?string {
	mut f := SvafFinder{}
	return c.svaf_affix(mut f, node, false)
}

fn (c &Checker) svaf_affix(mut f SvafFinder, node int, prefix bool) ?string {
	es := &c.svelte.doc.es
	if node < 0 {
		return none
	}
	match es.nodes[node].typ {
		.binary_expression {
			if prefix {
				left := es.node(node, .left)?
				if es.nodes[left].typ == .private_identifier {
					return none
				}
				return c.svaf_affix(mut f, left, prefix)
			}
			return c.svaf_affix(mut f, es.node(node, .right)?, prefix)
		}
		.identifier {
			init := c.svaf_init(c.svaf_find_variable(mut f, node))
			if init < 0 {
				return none
			}
			return c.svaf_affix(mut f, init, prefix)
		}
		.literal {
			value := es.get(node, .value)
			if value is string {
				return value
			}
			return none
		}
		.template_literal {
			mut parts := c.svaf_template_parts(node)
			if !prefix {
				parts.reverse_in_place()
			}
			for part in parts {
				if es.nodes[part].typ == .template_element {
					raw := c.svaf_raw(part)
					if raw == '' {
						continue
					}
					return raw
				}
				return c.svaf_affix(mut f, part, prefix)
			}
			return none
		}
		else {
			return none
		}
	}
}

// SvafCount is ElementOccurenceCount.
enum SvafCount {
	zero_or_one
	one
	zero_to_inf
}

fn svaf_multiply(left SvafCount, right SvafCount) SvafCount {
	if left == .one {
		return right
	}
	if right == .one {
		return left
	}
	if left == right {
		return left
	}
	return .zero_to_inf
}

// svaf_child_count is childElementOccurenceCount of a parent (-1: none).
fn (c &Checker) svaf_child_count(parent int) SvafCount {
	if parent < 0 {
		return .one
	}
	n := c.svelte.doc.nodes[parent]
	return match n.typ {
		.if_block, .else_block, .await_block, .await_pending_block, .await_then_block,
		.await_catch_block {
			.zero_or_one
		}
		.each_block, .snippet_block {
			.zero_to_inf
		}
		.element {
			if n.kind == 'component' { SvafCount.zero_to_inf } else { SvafCount.one }
		}
		else {
			.one
		}
	}
}

// svaf_occurrence_count is elementOccurrenceCount of a Svelte node.
fn (c &Checker) svaf_occurrence_count(element int) SvafCount {
	parent := c.svelte.doc.nodes[element].parent
	parent_count := if parent >= 0 { c.svaf_occurrence_count(parent) } else { SvafCount.one }
	return svaf_multiply(parent_count, c.svaf_child_count(parent))
}

// svaf_classes_in_attribute is findClassesInAttribute: the words of the literal parts of a `class`
// attribute (`value.trim().split(/\s+/u)`), or a class directive's name.
fn (c &Checker) svaf_classes_in_attribute(attr int) []string {
	doc := c.svelte.doc
	n := doc.nodes[attr]
	if n.typ == .attribute && c.sv_attribute_name(attr) == 'class' {
		mut out := []string{}
		for v in n.values {
			if doc.nodes[v].typ == .literal {
				out << svaf_split_spaces(postcss.js_trim(doc.nodes[v].value))
			}
		}
		return out
	}
	if n.typ == .directive && n.kind == 'Class' {
		return [c.sv_directive_key_name(attr)]
	}
	return []
}

// svaf_split_spaces is split(/\s+/u).
fn svaf_split_spaces(s string) []string {
	u := postcss.units(s)
	mut out := []string{}
	mut start := 0
	mut i := 0
	for i < u.len {
		if postcss.is_js_space(u[i]) {
			out << postcss.text(u[start..i])
			for i < u.len && postcss.is_js_space(u[i]) {
				i++
			}
			start = i
			continue
		}
		i++
	}
	out << postcss.text(u[start..])
	return out
}
