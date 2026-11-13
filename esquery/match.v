module esquery

import estree
import jsregexp

// The matcher of esquery 1.7.0 (generateMatcher, inPath, sibling, adjacent, nthChild) with the
// options ESLint 10.6.0 gives it (lib/linter/source-code-traverser.js): typescript-eslint's
// visitor keys, the JavaScript language's matchesSelectorClass for the classes, and `type` as the
// key of the node type.

// matches ports esquery.matches(node, selector, ancestry, options): whether the node matches.
// `ancestry` are the ancestors of the node, its parent first. It fails where esquery throws: a
// class other than statement, declaration, pattern, expression and function (ESLint's
// matchesSelectorClass throws "Unknown class name"), or a regular expression the matcher gives
// up on.
pub fn matches(t &estree.EsTree, node int, sel &Selector, ancestry []int) !bool {
	if sel.kind == .empty {
		return true
	}
	if node < 0 {
		return false
	}
	return match_sel(t, node, sel, ancestry)
}

fn match_sel(t &estree.EsTree, node int, sel &Selector, ancestry []int) !bool {
	match sel.kind {
		.empty, .wildcard {
			return true
		}
		.identifier {
			return js_lower(sel.value) == js_lower(t.typ(node).type_name())
		}
		.exact_node {
			return ancestry.len == 0
		}
		.field {
			if sel.path.len > ancestry.len {
				return false
			}
			return in_path(t, node, node_value(ancestry[sel.path.len - 1]), sel.path, 0)
		}
		.matches {
			for s in sel.selectors {
				if match_sel(t, node, s, ancestry)! {
					return true
				}
			}
			return false
		}
		.compound {
			for s in sel.selectors {
				if !match_sel(t, node, s, ancestry)! {
					return false
				}
			}
			return true
		}
		.not {
			for s in sel.selectors {
				if match_sel(t, node, s, ancestry)! {
					return false
				}
			}
			return true
		}
		.has {
			return has_visit(t, node, []int{}, sel.selectors)
		}
		.child {
			if ancestry.len > 0 && match_sel(t, node, sel.selectors[1], ancestry)! {
				return match_sel(t, ancestry[0], sel.selectors[0], ancestry[1..])
			}
			return false
		}
		.descendant {
			if match_sel(t, node, sel.selectors[1], ancestry)! {
				for i in 0 .. ancestry.len {
					if match_sel(t, ancestry[i], sel.selectors[0], ancestry[i + 1..])! {
						return true
					}
				}
			}
			return false
		}
		.attribute {
			return match_attribute(t, node, sel)
		}
		.sibling {
			left := &sel.selectors[0]
			right := &sel.selectors[1]
			if match_sel(t, node, right, ancestry)! && sibling(t, node, left, ancestry, true)! {
				return true
			}
			return left.subject && match_sel(t, node, left, ancestry)!
				&& sibling(t, node, right, ancestry, false)!
		}
		.adjacent {
			left := &sel.selectors[0]
			right := &sel.selectors[1]
			if match_sel(t, node, right, ancestry)! && adjacent(t, node, left, ancestry, true)! {
				return true
			}
			// esquery asks the right side's `!` here (the left side's for `~`).
			return right.subject && match_sel(t, node, left, ancestry)!
				&& adjacent(t, node, right, ancestry, false)!
		}
		.nth_child {
			return nth_child(t, node, ancestry, sel.index)
		}
		.nth_last_child {
			return nth_child(t, node, ancestry, -sel.index)
		}
		.class {
			return match_class(t, node, sel.name, ancestry)
		}
	}
}

// has_visit is the traversal of `:has`: estraverse from the node (included), with the ancestry
// relative to it, until a selector matches.
fn has_visit(t &estree.EsTree, v int, a []int, sels []Selector) !bool {
	for s in sels {
		if match_sel(t, v, s, a)! {
			return true
		}
	}
	children := t.children(v)
	if children.len == 0 {
		return false
	}
	mut inner := [v]
	inner << a
	for c in children {
		if has_visit(t, c, inner, sels)! {
			return true
		}
	}
	return false
}

// in_path ports esquery's inPath: whether `node` is reached from `current` by the keys of `path`
// from `from`, through every element of the arrays on the way.
fn in_path(t &estree.EsTree, node int, current JVal, path []string, from int) bool {
	mut cur := current
	for i in from .. path.len {
		if cur.kind in [.undefined, .null] {
			return false
		}
		field := get_prop(t, cur, path[i])
		if field.kind == .list {
			for item in t.lists[field.idx] {
				if in_path(t, node, node_value(item), path, i + 1) {
					return true
				}
			}
			return false
		}
		if field.kind == .range {
			// An array of two numbers, none of which leads to a node.
			return false
		}
		cur = field
	}
	return cur.kind == .node && cur.idx == node
}

// list_props are the arrays among the visitor keys of a node (getVisitorKeys, then the arrays).
fn list_props(t &estree.EsTree, parent int) [][]int {
	mut out := [][]int{}
	for key in estree.keys_of(t.typ(parent)) {
		if items := t.list(parent, key) {
			out << items
		}
	}
	return out
}

// sibling ports esquery's sibling: whether a node before (`left`) or after the node in a list of
// its parent matches.
fn sibling(t &estree.EsTree, node int, sel &Selector, ancestry []int, left bool) !bool {
	if ancestry.len == 0 {
		return false
	}
	for items in list_props(t, ancestry[0]) {
		start := items.index(node)
		if start < 0 {
			continue
		}
		lower, upper := if left { 0, start } else { start + 1, items.len }
		for k in lower .. upper {
			if items[k] >= 0 && match_sel(t, items[k], sel, ancestry)! {
				return true
			}
		}
	}
	return false
}

// adjacent ports esquery's adjacent: the node just before (`left`) or after.
fn adjacent(t &estree.EsTree, node int, sel &Selector, ancestry []int, left bool) !bool {
	if ancestry.len == 0 {
		return false
	}
	for items in list_props(t, ancestry[0]) {
		idx := items.index(node)
		if idx < 0 {
			continue
		}
		if left && idx > 0 && items[idx - 1] >= 0 && match_sel(t, items[idx - 1], sel, ancestry)! {
			return true
		}
		if !left && idx < items.len - 1 && items[idx + 1] >= 0
			&& match_sel(t, items[idx + 1], sel, ancestry)! {
			return true
		}
	}
	return false
}

// nth_child ports esquery's nthChild: the node is the nth element of a list of its parent
// (counted from the end when nth is negative).
fn nth_child(t &estree.EsTree, node int, ancestry []int, nth f64) bool {
	if nth == 0 || ancestry.len == 0 {
		return false
	}
	for items in list_props(t, ancestry[0]) {
		idx := if nth < 0 { f64(items.len) + nth } else { nth - 1 }
		if idx >= 0 && idx < f64(items.len) && items[int(idx)] == node {
			return true
		}
	}
	return false
}

// match_class ports matchesSelectorClass of ESLint's JavaScript language (lib/languages/js).
fn match_class(t &estree.EsTree, node int, name string, ancestry []int) !bool {
	typ := t.typ(node).type_name()
	lower := js_lower(name)
	if lower in ['statement', 'declaration'] {
		if lower == 'statement' && typ.ends_with('Statement') {
			return true
		}
		return typ.ends_with('Declaration')
	}
	if lower in ['pattern', 'expression'] {
		if lower == 'pattern' && typ.ends_with('Pattern') {
			return true
		}
		return typ.ends_with('Expression') || typ.ends_with('Literal')
			|| (typ == 'Identifier' && (ancestry.len == 0 || t.typ(ancestry[0]) != .meta_property))
			|| typ == 'MetaProperty'
	}
	if lower == 'function' {
		return typ in ['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression']
	}
	return error('Unknown class name: ${name}')
}

fn match_attribute(t &estree.EsTree, node int, sel &Selector) !bool {
	value := get_path(t, node, sel.path)
	match sel.operator {
		'' {
			return value.kind !in [.undefined, .null]
		}
		'=', '!=' {
			eq := sel.operator == '='
			match sel.value_kind {
				.regexp {
					if eq {
						return value.kind == .string && sel.regex.test(utf16_units(value.s))!
					}
					return !sel.regex.test(utf16_units(js_string(t, value)))!
				}
				.type {
					return (sel.str_value == js_typeof(value)) == eq
				}
				else {
					return (sel.str_value == js_string(t, value)) == eq
				}
			}
		}
		else {
			x := to_primitive(t, value)
			y := if sel.is_number {
				Primitive{
					kind: .number
					n:    sel.num_value
				}
			} else {
				Primitive{
					kind: .string
					s:    sel.str_value
				}
			}
			return match sel.operator {
				'<' { js_less(x, y) or { false } }
				'>' { js_less(y, x) or { false } }
				'<=' { !(js_less(y, x) or { true }) }
				else { !(js_less(x, y) or { true }) }
			}
		}
	}
}

// js_lower ports String.prototype.toLowerCase.
fn js_lower(s string) string {
	if s.bytes().all(it < 0x80) {
		return s.to_lower()
	}
	return units_to_string(jsregexp.js_to_lower(utf16_units(s)))
}
