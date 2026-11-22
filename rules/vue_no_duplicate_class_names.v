module rules

import estree
import time

// Port of the `vue/no-duplicate-class-names` rule of eslint-plugin-vue 10.12.1 (no options): a
// class name twice in a static `class`, in a string or a template element of a `:class` (both
// fixed), in a `:class` and the static `class`, and in two parts of a `:class` that can apply
// together.

const vndcn_messages = {
	'duplicateClassNames': 'Duplicate class name{{plural}} {{names}}.'
}

// VndcnClass is a node extractClassNodes yields: a Literal or a TemplateElement of the snippet,
// whether it always applies, and the expression that combines it (-1 for none).
struct VndcnClass {
	node          int
	unconditional bool
	parent_expr   int = -1
}

// vndcn_extract is extractClassNodes.
fn vndcn_extract(t &estree.EsTree, expr int, unconditional bool, parent_expr int, mut out []VndcnClass) {
	if expr < 0 {
		return
	}
	match t.typ(expr) {
		.literal {
			out << VndcnClass{expr, unconditional, parent_expr}
		}
		.object_expression {
			for prop in t.list(expr, .properties) or { []int{} } {
				if t.typ(prop) != .property {
					continue
				}
				key := t.node(prop, .key) or { continue }
				if t.typ(key) == .literal && t.get(key, .value) is string {
					out << VndcnClass{key, false, expr}
				}
			}
		}
		.array_expression {
			for element in t.list(expr, .elements) or { []int{} } {
				if element < 0 || t.typ(element) == .spread_element {
					continue
				}
				vndcn_extract(t, element, unconditional, expr, mut out)
			}
		}
		.conditional_expression {
			vndcn_extract(t, t.node(expr, .consequent) or { -1 }, false, expr, mut out)
			vndcn_extract(t, t.node(expr, .alternate) or { -1 }, false, expr, mut out)
		}
		.template_literal {
			for quasi in t.list(expr, .quasis) or { []int{} } {
				out << VndcnClass{quasi, unconditional, expr}
			}
			for e in t.list(expr, .expressions) or { []int{} } {
				vndcn_extract(t, e, unconditional, expr, mut out)
			}
		}
		.binary_expression {
			if (t.string_of(expr, .operator) or { '' }) == '+' {
				vndcn_extract(t, t.node(expr, .left) or { -1 }, unconditional, expr, mut out)
				vndcn_extract(t, t.node(expr, .right) or { -1 }, unconditional, expr, mut out)
			}
		}
		.logical_expression {
			vndcn_extract(t, t.node(expr, .left) or { -1 }, unconditional, expr, mut out)
			vndcn_extract(t, t.node(expr, .right) or { -1 }, false, expr, mut out)
		}
		else {}
	}
}

// vndcn_raw_value is getRawValue of a Literal or a TemplateElement: a string Literal's value, a
// TemplateElement's raw text (none for anything else, and for an empty or falsy value).
fn vndcn_raw_value(t &estree.EsTree, node int) ?string {
	v := t.get(node, .value)
	if v is estree.TemplateValue {
		return v.raw
	}
	if v is string && v != '' {
		return v
	}
	return none
}

// vndcn_class_names is getClassNames: `split(/\s+/).filter(Boolean)`.
fn vndcn_class_names(list string) []string {
	return vue_split_whitespace(list).filter(it != '')
}

fn vndcn_all_space(s string) bool {
	return s != '' && s.runes().all(is_js_space(it))
}

// vndcn_split_keep is `s.split(/(\s+)/)`: the pieces between the runs of white space with the
// runs (an empty piece first or last when s starts or ends with white space).
fn vndcn_split_keep(s string) []string {
	mut out := []string{}
	mut current := []rune{}
	mut in_space := false
	for r in s.runes() {
		space := is_js_space(r)
		if space != in_space {
			out << current.string()
			current = []rune{}
			in_space = space
		}
		current << r
	}
	out << current.string()
	if in_space {
		out << ''
	}
	return out
}

// vndcn_first_part is `s.split(/(\s+)/)[0]`.
fn vndcn_first_part(s string) string {
	return vndcn_split_keep(s)[0]
}

// vndcn_remove_duplicates is removeDuplicateClassNames of the text of a node, quotes included
// (its first and last characters, whatever they are).
fn vndcn_remove_duplicates(raw string) string {
	units := utf16_units(raw)
	quote := utf16_to_string(units[..1])
	inner := if units.len >= 2 { utf16_to_string(units[1..units.len - 1]) } else { '' }
	tokens := vndcn_split_keep(inner)
	mut kept := []string{}
	mut used := map[string]bool{}
	mut i := 0
	for i < tokens.len {
		token := tokens[i]
		if token == '' {
			i++
			continue
		}
		if vndcn_all_space(token) {
			if kept.len > 0 {
				kept[kept.len - 1] += token
			} else {
				kept << token
			}
		} else if token in used {
			if kept.len > 0 && i + 1 < tokens.len && vndcn_all_space(tokens[i + 1]) {
				next := tokens[i + 1]
				for j := kept.len - 1; j >= 0; j-- {
					if !vndcn_all_space(kept[j]) {
						kept[j] = vndcn_first_part(kept[j]) + next
						break
					}
				}
				i++
			}
		} else {
			kept << token
			used[token] = true
		}
		i++
	}
	has_trailing_space := inner.len > 0 && is_js_space(inner.runes().last())
	if kept.len > 0 && kept.last() != '' && !has_trailing_space && !vndcn_all_space(kept.last()) {
		kept[kept.len - 1] = vndcn_first_part(kept.last())
	}
	return quote + kept.join('') + quote
}

fn vndcn_names_data(list []string) map[string]string {
	return {
		'names':  list.map("'${it}'").join(', ')
		'plural': if list.len > 1 { 's' } else { '' }
	}
}

// vndcn_report_duplicates is reportDuplicateClasses on [start, end) with the class list `list`:
// the report with its fix, and the duplicate names (none when there are none).
fn (c &Checker) vndcn_report_duplicates(start int, end int, list string, mut findings []Finding) ![]string {
	class_names := vndcn_class_names(list)
	if class_names.len <= 1 {
		return []
	}
	mut seen := map[string]bool{}
	mut duplicates := []string{}
	for name in class_names {
		if name in seen {
			if name !in duplicates {
				duplicates << name
			}
		} else {
			seen[name] = true
		}
	}
	if duplicates.len == 0 {
		return []
	}
	f := c.vue_report(start, end, 'duplicateClassNames', vndcn_names_data(duplicates))
	findings << c.with_fixes(f, [
		fix_replace_range(start, end, vndcn_remove_duplicates(c.src[start..end])),
	])!
	return duplicates
}

// VndcnCollected is what collectClassName keeps of the first node of a class name: the range of
// its parent (the report's node), whether it always applies, and its combining expression.
struct VndcnCollected {
	start         int
	end           int
	unconditional bool
	parent_expr   int
}

fn (mut c Checker) lint_vue_no_duplicate_class_names(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute {
			continue
		}
		key := &c.vue.doc.nodes[node.key]
		if !node.directive {
			// VAttribute[directive=false][key.name='class'][value.type='VLiteral']
			if key.name == 'class' && node.value >= 0 {
				stats.checked++
				literal := &c.vue.doc.nodes[node.value]
				if literal.text != '' {
					c.vndcn_report_duplicates(literal.start, literal.end, literal.text, mut
						findings)!
				}
			}
			continue
		}
		if key.argument < 0 || c.vue.doc.nodes[key.argument].typ != .v_identifier
			|| c.vue.doc.nodes[key.argument].name != 'class' || node.value < 0 {
			continue
		}
		stats.checked++
		c.vndcn_directive(i, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vndcn_directive is the listener of a directive with the argument `class`.
fn (c &Checker) vndcn_directive(attr int, mut findings []Finding) ! {
	node := &c.vue.doc.nodes[attr]
	start_tag := c.vue.doc.nodes[attr].parent
	mut static_classes := ?[]string(none)
	for a in c.vue.doc.nodes[start_tag].attributes {
		other := &c.vue.doc.nodes[a]
		if !other.directive && c.vue.doc.nodes[other.key].name == 'class' && other.value >= 0 {
			static_classes = vndcn_class_names(c.vue.doc.nodes[other.value].text)
			break
		}
	}
	container := node.value
	e := c.vue.doc.nodes[container].expression
	if e.kind != .estree {
		return
	}
	t := &c.vue.doc.snippets[e.snippet].es
	mut classes := []VndcnClass{}
	vndcn_extract(t, e.node, true, -1, mut classes)
	mut reported := []string{}
	mut duplicates := []string{}
	mut seen := map[string][]int{}
	mut collected := map[string]VndcnCollected{}
	for class in classes {
		// The report's node of the cross-node duplicates is the parent, the VExpressionContainer
		// for the expression itself.
		p_start, p_end := if class.node == e.node {
			c.vue_vnode_range(container)
		} else {
			parent := t.nodes[class.node].parent
			t.nodes[parent].start, t.nodes[parent].end
		}
		list := vndcn_raw_value(t, class.node) or { continue }
		for name in c.vndcn_report_duplicates(t.nodes[class.node].start, t.nodes[class.node].end,
			list, mut findings)! {
			if name !in reported {
				reported << name
			}
		}
		class_names := vndcn_class_names(list)
		for name in class_names {
			if name in reported {
				continue
			}
			if existing := collected[name] {
				same_parent := class.parent_expr >= 0 && existing.parent_expr == class.parent_expr
					&& t.typ(class.parent_expr) in [.binary_expression, .template_literal]
				if (class.unconditional || same_parent || existing.unconditional)
					&& name !in duplicates {
					duplicates << name
				}
			} else {
				collected[name] = VndcnCollected{p_start, p_end, class.unconditional, class.parent_expr}
			}
			if class.unconditional {
				if name in seen {
					if name !in duplicates {
						duplicates << name
					}
				} else {
					seen[name] = [p_start, p_end]
				}
			}
		}
		statics := static_classes or { continue }
		intersection := class_names.filter(it in statics)
		if intersection.len > 0 {
			findings << c.vue_report_vnode(start_tag, 'duplicateClassNames', vndcn_names_data(intersection))
		}
	}
	for name in duplicates {
		mut start, mut end := -1, -1
		if r := seen[name] {
			start, end = r[0], r[1]
		} else if col := collected[name] {
			start, end = col.start, col.end
		}
		if start >= 0 {
			findings << c.vue_report(start, end, 'duplicateClassNames', vndcn_names_data([name]))
		}
	}
}
