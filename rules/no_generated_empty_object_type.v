module rules

import time
import tsgo { TypeResponse }

// Port of the `@typescript-eslint/no-generated-empty-object-type` rule of typescript-eslint
// 8.72.2 (it has no options): the types of the intersection types and of the type references with
// type arguments, as getTypeAtLocation gives them (getTypeFromTypeNode).

const ngeo_messages = {
	'noGeneratedEmptyObjectType': 'This type resolves to `{}`, the empty object type. This was likely not intentional.'
}

fn (mut c Checker) lint_no_generated_empty_object_type(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut nodes := []int{}
	mut spans := []Span{}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		match t.typ(node) {
			.ts_intersection_type {}
			.ts_type_reference {
				parent := t.nodes[node].parent
				if t.node(node, .type_arguments) == none
					|| (parent >= 0 && t.typ(parent) == .ts_intersection_type) {
					continue
				}
			}
			else {
				continue
			}
		}
		ts := t.ts_node(node) or { continue }
		nodes << node
		spans << c.type_node_span(ts)
	}
	stats.checked += nodes.len
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	for i, node in nodes {
		typ := c.span_type(spans[i]) or { continue }
		if c.ngeo_contains_empty_object_type(typ)! {
			findings << Finding{
				stmt:       c.es_tree_position(t, node)
				message_id: 'noGeneratedEmptyObjectType'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// ngeo_is_empty_object_type ports isEmptyObjectType.
fn (mut c Checker) ngeo_is_empty_object_type(typ TypeResponse) !bool {
	if typ.flags & type_flag_object == 0 || typ.object_flags & object_flags_class_or_interface != 0 {
		return false
	}
	if c.properties(typ)!.len != 0 || c.index_infos(typ.id)!.len != 0
		|| c.signatures_of(typ, signature_kind_call)!.len != 0
		|| c.signatures_of(typ, signature_kind_construct)!.len != 0 {
		return false
	}
	// Types still awaiting type arguments have no members either: every primitive is assignable
	// to `{}`, so number and string both are.
	return c.assignable(c.intrinsic('getNumberType')!.id, typ.id)!
		&& c.assignable(c.intrinsic('getStringType')!.id, typ.id)!
}

// ngeo_contains_empty_object_type ports containsEmptyObjectType.
fn (mut c Checker) ngeo_contains_empty_object_type(typ TypeResponse) !bool {
	if c.ngeo_is_empty_object_type(typ)! {
		return true
	}
	if typ.flags & type_flag_union != 0 {
		for member in c.members_of(typ)! {
			if c.ngeo_is_empty_object_type(member)! {
				return true
			}
		}
	}
	return false
}
