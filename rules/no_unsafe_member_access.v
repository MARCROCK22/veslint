module rules

import json2
import time
import treesitter { children, first_named_child, has_child_kind, named_children, node_end, node_field, node_kind, node_start, nodes_of_kind, nodes_of_kinds, position_of }

// Port of the `no-unsafe-member-access` rule of typescript-eslint 8.62.0 with its option,
// allowOptionalChaining. Limits of the port: README, "Rules" section.

const numa_messages = {
	'errorComputedMemberAccess':  'The type of computed name {{property}} cannot be resolved.'
	'errorMemberExpression':      'Unsafe member access {{property}} on a type that cannot be resolved.'
	'errorThisMemberExpression':  'Unsafe member access {{property}}. The type of `this` cannot be resolved.\nYou can try to fix this by turning on the `noImplicitThis` compiler option, or adding a `this` parameter to the function.'
	'unsafeComputedMemberAccess': 'Computed name {{property}} resolves to an `any` value.'
	'unsafeMemberExpression':     'Unsafe member access {{property}} on an `any` value.'
	'unsafeThisMemberExpression': 'Unsafe member access {{property}} on an `any` value. `this` is typed as `any`.\nYou can try to fix this by turning on the `noImplicitThis` compiler option, or adding a `this` parameter to the function.'
}

const member_kinds = ['member_expression', 'subscript_expression']

// The subtrees that hold a name and not an expression, where the grammar has member_expression
// nodes and ESTree a TSQualifiedName: `typeof a.b` in a type, the qualifier of a name with three
// or more parts (`a.b.c.T`, `import x = a.b.c`) and an import type (`import('./x').A.B`).
const type_name_kinds = ['type_query', 'nested_identifier', 'import_type']

// A computed name that is an ESTree literal or an `i++` is not checked.
const literal_or_update_kinds = ['string', 'number', 'true', 'false', 'null', 'regex',
	'update_expression']

// AwaitAccess is an `await [i]` outside an async function, which TypeScript reads as the element
// access `await[i]` (see await_reading). The index is the element without parentheses, or `a, b`
// if there are several.
struct AwaitAccess {
	node    C.TSNode // the await_expression
	index   Span
	first   C.TSNode // first token of the index, where the rule reports
	text    string   // the index as ESTree writes it (sourceCode.getText)
	literal bool     // a literal or an `i++`, not checked as a computed name
}

// numa_options reads allowOptionalChaining: an access with `?.` is not checked.
fn numa_options(options []json2.Any) !bool {
	o := option_object(no_unsafe_member_access, options, ['allowOptionalChaining'])!
	return o.bool_value('allowOptionalChaining')!
}

fn (mut c Checker) lint_no_unsafe_member_access(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	allow_optional := numa_options(c.rule_options(no_unsafe_member_access))!
	members := c.nodes_of_kinds(root, member_kinds, type_name_kinds)
	mut spans := []Span{}
	for m in members {
		if object := node_field(m, 'object') {
			spans << node_span(unwrap_parens(object))
		}
		if node_kind(m) == 'subscript_expression' {
			if index := node_field(m, 'index') {
				spans << node_span(unwrap_parens(index))
			}
		}
	}
	spans << c.this_spans(members)
	accesses := c.await_accesses(root)
	for a in accesses {
		spans << node_span(a.node)
		spans << a.index
		spans << await_keyword_span(a.node) or { continue }
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	mut states := map[u64]bool{}
	for m in members {
		c.check_member(m, 0, allow_optional, mut states, mut findings)!
		// `MemberExpression[computed = true] > *.property`
		if node_kind(m) != 'subscript_expression' {
			continue
		}
		if allow_optional && has_child_kind(m, 'optional_chain') {
			continue
		}
		index := unwrap_parens(node_field(m, 'index') or { continue })
		if node_kind(index) in literal_or_update_kinds {
			continue
		}
		t := c.node_type(index) or { continue }
		if c.is_any(t)! {
			findings << Finding{
				stmt:       position_of(index)
				message_id: if is_error_type(t) {
					'errorComputedMemberAccess'
				} else {
					'unsafeComputedMemberAccess'
				}
				data:       {
					'property': '[${c.text(index)}]'
				}
			}
		}
	}
	for a in accesses {
		c.check_await_access(a, mut findings)!
	}
	findings.sort_with_compare(compare_findings)
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += members.len + accesses.len
	return findings
}

// await_accesses collects the `await [i]` TypeScript may read as an element access: without
// holes or `...`, which would not be an index.
fn (c &Checker) await_accesses(root C.TSNode) []AwaitAccess {
	mut out := []AwaitAccess{}
	for node in c.nodes_of_kind(root, c'await_expression') {
		array := first_named_child(node) or { continue }
		if node_kind(array) != 'array' {
			continue
		}
		elements := named_children(array)
		commas := children(array).filter(node_kind(it) == ',').len
		if elements.len == 0 || commas != elements.len - 1
			|| elements.any(node_kind(it) == 'spread_element') {
			continue
		}
		if elements.len == 1 {
			index := unwrap_parens(elements[0])
			out << AwaitAccess{
				node:    node
				index:   node_span(index)
				first:   index
				text:    c.text(index)
				literal: node_kind(index) in literal_or_update_kinds
			}
		} else {
			out << AwaitAccess{
				node:  node
				// In a real `await`, `a, b` is not a TypeScript node, and it does not count.
				index: Span{
					...range_span(elements[0], elements.last())
					optional: true
				}
				first: elements[0]
				text:  c.src[node_start(elements[0])..node_end(elements.last())]
			}
		}
	}
	return out
}

// check_await_access applies checkMemberExpression and the computed-name check to an `await[i]`,
// whose object is the `await` identifier.
fn (mut c Checker) check_await_access(a AwaitAccess, mut findings []Finding) ! {
	if c.await_reading(a.node) != .element_access {
		return
	}
	keyword := await_keyword(a.node) or { return }
	if t := c.node_type(keyword) {
		if c.is_any(t)! {
			findings << Finding{
				stmt:       position_of(a.first)
				message_id: if is_error_type(t) {
					'errorMemberExpression'
				} else {
					'unsafeMemberExpression'
				}
				data:       {
					'property': '[${a.text}]'
				}
			}
		}
	}
	if a.literal {
		return
	}
	t := c.span_type(a.index) or { return }
	if c.is_any(t)! {
		findings << Finding{
			stmt:       position_of(a.first)
			message_id: if is_error_type(t) {
				'errorComputedMemberAccess'
			} else {
				'unsafeComputedMemberAccess'
			}
			data:       {
				'property': '[${a.text}]'
			}
		}
	}
}

// check_member ports checkMemberExpression: in a chain `a.b.c` on an `any` only the first unsafe
// access is reported; the next ones inherit the state. Returns whether the access is unsafe. With
// allowOptionalChaining, an access with `?.` is "chained": not checked and not unsafe, so the
// access after it is checked on its own.
fn (mut c Checker) check_member(m C.TSNode, depth int, allow_optional bool, mut states map[u64]bool, mut findings []Finding) !bool {
	key := node_key(m)
	if allow_optional && has_child_kind(m, 'optional_chain') {
		states[key] = false
		return false
	}
	if key in states {
		return states[key]
	}
	if depth > max_expression_depth {
		c.too_deep++
		states[key] = false
		return false
	}
	object := unwrap_parens(node_field(m, 'object') or { return false })
	// The state of the object is only inherited from a MemberExpression: an optional chain in
	// parentheses is a ChainExpression for ESTree, and the access after it is checked on its own.
	if node_kind(object) in member_kinds && estree_type(object) == 'MemberExpression'
		&& c.check_member(object, depth + 1, allow_optional, mut states, mut findings)! {
		states[key] = true
		return true
	}
	t := c.node_type(object) or {
		states[key] = false
		return false
	}
	is_unsafe := c.is_any(t)!
	states[key] = is_unsafe
	if !is_unsafe {
		return false
	}
	property, text := if node_kind(m) == 'subscript_expression' {
		index := unwrap_parens(node_field(m, 'index') or { return true })
		index, '[${c.text(index)}]'
	} else {
		prop := node_field(m, 'property') or { return true }
		prop, '.${c.text(prop)}'
	}
	mut message_id := if is_error_type(t) {
		'errorMemberExpression'
	} else {
		'unsafeMemberExpression'
	}
	if !c.no_implicit_this {
		if this := this_expression(m) {
			if this_type := c.node_type(this) {
				constrained := c.constrained(this_type)!
				if c.is_any(constrained)! {
					message_id = if is_error_type(constrained) {
						'errorThisMemberExpression'
					} else {
						'unsafeThisMemberExpression'
					}
				}
			}
		}
	}
	findings << Finding{
		stmt:       position_of(property)
		message_id: message_id
		data:       {
			'property': text
		}
	}
	return true
}
