module rules

import json2
import postcss
import tsgo { SymbolResponse, TypeResponse }
import treesitter { node_end, node_field, node_kind, node_parent, node_start }

// Port of the `svelte/require-event-prefix` rule of eslint-plugin-svelte 3.24.1: in a Svelte 5
// component, a property of the type of `… = $props()` that is a function (a method, or a property
// whose declared type is a function type) whose name does not start with "on" and that looks like
// an event: all its call signatures return nothing (void, undefined or null) or, with
// checkAsyncFunctions, a promise of nothing, and at least one returns nothing unless
// checkAsyncFunctions. In a component with `generics`, a signature counts only when its declared
// return type says so in its syntax. Reported at the property's declaration when it is in the
// component, else at the $props() call.

const srep_messages = {
	'nonPrefixedFunction': 'Component event name must start with "on".'
}

// TypeScript 7.1's SyntaxKind and SymbolFlags values this rule reads.
const srep_kind_property_signature = u32(173)
const srep_kind_function_type = u32(186)
const srep_kind_parenthesized_type = u32(198)
const srep_kind_union_type = u32(194)
const srep_kind_type_reference = u32(185)
const srep_kind_literal_type = u32(203)
const srep_kind_identifier = u32(79)
const srep_kind_void_keyword = u32(115)
const srep_kind_undefined_keyword = u32(157)
const srep_kind_null_keyword = u32(105)
const srep_symbol_flag_method = u32(8192)

fn srep_options(options []json2.Any) !bool {
	o := option_object(svelte_require_event_prefix, options, ['checkAsyncFunctions'])!
	return if 'checkAsyncFunctions' in o.values {
		o.bool_value('checkAsyncFunctions')!
	} else {
		false
	}
}

enum SrepKind {
	void
	async
	other
}

fn (mut c Checker) lint_svelte_require_event_prefix(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	check_async := srep_options(c.rule_options(svelte_require_event_prefix))!
	// conditions: Svelte 5 components; getTypeScriptTools: a program.
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut has_generics := false
	for ch in doc.nodes[0].children {
		if doc.nodes[ch].typ == .script_element && doc.nodes[ch].start_tag >= 0 {
			for a in doc.nodes[doc.nodes[ch].start_tag].attributes {
				if doc.nodes[a].typ == .generics_directive {
					has_generics = true
				}
			}
		}
	}
	mut calls := []C.vt_node{}
	mut ids := []C.vt_node{}
	for call in c.nodes_of_kind(root, c'call_expression') {
		callee := node_field(call, 'function') or { continue }
		if node_kind(callee) != 'identifier' || c.text(callee) != '\$props' {
			continue
		}
		parent := node_parent(call) or { continue }
		if node_kind(parent) != 'variable_declarator' {
			continue
		}
		value := node_field(parent, 'value') or { continue }
		if node_start(value) != node_start(call) || node_end(value) != node_end(call) {
			continue
		}
		calls << call
		ids << node_field(parent, 'name') or { continue }
	}
	if calls.len == 0 {
		return []
	}
	c.resolve_node_types(ids, abs_path, mut stats)!
	mut findings := []Finding{}
	for k, call in calls {
		props := c.node_type(ids[k]) or { continue }
		for property in c.properties(props)! {
			if !c.srep_function_like(property)! || property.name.starts_with('on')
				|| !c.srep_event_like(property, check_async, has_generics)! {
				continue
			}
			findings << c.srep_report(property, call)!
		}
	}
	return findings
}

// srep_ast is the AstTree of a tsgo handle's file and the handle's node in it.
fn (mut c Checker) srep_ast(handle string) !(tsgo.AstTree, int) {
	tree := c.declaration_ast(tsgo.handle_path(handle))!
	return tree, tsgo.handle_index(handle)
}

// srep_function_like is isFunctionLike: a method, or a property signature whose type is a
// function type.
fn (mut c Checker) srep_function_like(property SymbolResponse) !bool {
	if property.flags & srep_symbol_flag_method != 0 {
		return true
	}
	if property.value_declaration == ''
		|| tsgo.handle_kind(property.value_declaration) != srep_kind_property_signature {
		return false
	}
	tree, index := c.srep_ast(property.value_declaration)!
	typ := tree.node_child(index, 'type')
	return typ != 0 && tree.node_kind(typ) == srep_kind_function_type
}

// srep_event_like is isEventLike.
fn (mut c Checker) srep_event_like(property SymbolResponse, check_async bool, has_generics bool) !bool {
	declaration := if property.value_declaration != '' {
		property.value_declaration
	} else if property.declarations.len > 0 {
		property.declarations[0]
	} else {
		return false
	}
	t := c.symbol_type_at(property, SymbolLocation{
		handle: declaration
	})!
	signatures := c.srep_call_signatures(t, 0)!
	if signatures.len == 0 {
		return false
	}
	mut kinds := []SrepKind{}
	for s in signatures {
		if has_generics && !c.srep_explicit_no_value_of(s.declaration)! {
			kinds << .other
			continue
		}
		kinds << c.srep_return_kind(c.return_type(s.id)!, 0)!
	}
	return SrepKind.other !in kinds && (SrepKind.void in kinds || check_async)
}

// srep_call_signatures is getCallSignaturesOfType of ts-utils: those of each member of a union,
// those of the one member of an intersection that has some (none when several have).
fn (mut c Checker) srep_call_signatures(t TypeResponse, depth int) ![]tsgo.SignatureResponse {
	if depth > 50 {
		return []
	}
	if t.flags & type_flag_union != 0 {
		mut out := []tsgo.SignatureResponse{}
		for part in c.members_of(t)! {
			out << c.srep_call_signatures(part, depth + 1)!
		}
		return out
	}
	if t.flags & type_flag_intersection != 0 {
		mut out := []tsgo.SignatureResponse{}
		for part in c.members_of(t)! {
			sigs := c.srep_call_signatures(part, depth + 1)!
			if sigs.len != 0 {
				if out.len > 0 {
					return []
				}
				out = sigs.clone()
			}
		}
		return out
	}
	return c.signatures_of(t, signature_kind_call)!
}

// srep_explicit_no_value_of is isExplicitNoValue of the declared return type of a signature's
// declaration.
fn (mut c Checker) srep_explicit_no_value_of(declaration string) !bool {
	if declaration == '' {
		return false
	}
	tree, index := c.srep_ast(declaration)!
	typ := tree.node_child(index, 'type')
	return typ != 0 && srep_explicit_no_value(&tree, typ)
}

// srep_explicit_no_value is isExplicitNoValue: void, undefined, null, or a promise of those,
// through parentheses and unions.
fn srep_explicit_no_value(tree &tsgo.AstTree, node int) bool {
	if node == 0 {
		return false
	}
	kind := tree.node_kind(node)
	match kind {
		srep_kind_parenthesized_type {
			return srep_explicit_no_value(tree, tree.node_child(node, 'type'))
		}
		srep_kind_union_type {
			types := tree.node_child(node, 'types')
			return types != 0 && tree.node_children(types).all(srep_explicit_no_value(tree, it))
		}
		srep_kind_type_reference {
			name := tree.node_child(node, 'typeName')
			args := tree.node_child(node, 'typeArguments')
			if name == 0 || tree.node_kind(name) != srep_kind_identifier
				|| tree.node_text(name) !in ['Promise', 'PromiseLike'] || args == 0 {
				return false
			}
			list := tree.node_children(args)
			return list.len == 1 && srep_explicit_no_value(tree, list[0])
		}
		srep_kind_void_keyword, srep_kind_undefined_keyword {
			return true
		}
		srep_kind_literal_type {
			literal := tree.node_child(node, 'literal')
			return literal != 0 && tree.node_kind(literal) == srep_kind_null_keyword
		}
		else {
			return false
		}
	}
}

// srep_return_kind is getReturnKind.
fn (mut c Checker) srep_return_kind(t TypeResponse, depth int) !SrepKind {
	if t.flags & (type_flag_void | type_flag_undefined | type_flag_null) != 0 {
		return .void
	}
	if depth > 50 {
		return .other
	}
	if t.flags & type_flag_union != 0 {
		mut kinds := []SrepKind{}
		for part in c.members_of(t)! {
			kinds << c.srep_return_kind(part, depth + 1)!
		}
		if SrepKind.other in kinds {
			return .other
		}
		return if SrepKind.void in kinds { SrepKind.void } else { SrepKind.async }
	}
	if c.property(t, 'then')!.id == 0 {
		return .other
	}
	awaited := c.awaited_type(t)!
	if !awaited.found || awaited.typ.id == t.id {
		return .other
	}
	return if c.srep_return_kind(awaited.typ, depth + 1)! == .other {
		SrepKind.other
	} else {
		SrepKind.async
	}
}

// srep_report reports at the property's first declaration when it is a node of the component
// (tsNodeToESTreeNodeMap), else at the $props() call.
fn (mut c Checker) srep_report(property SymbolResponse, call C.vt_node) !Finding {
	doc := c.svelte.doc
	if property.declarations.len > 0 && tsgo.handle_path(property.declarations[0]) == c.svelte.ts_path {
		tree, index := c.srep_ast(property.declarations[0])!
		start := tree.node_token_start(index)
		end := tree.node_end_byte(index)
		if start >= 0 && end >= start && end <= doc.virtual_code.len {
			file_start := doc.virtual_to_file(postcss.u16_len(doc.virtual_code[..start]), false)
			file_end := doc.virtual_to_file(postcss.u16_len(doc.virtual_code[..end]), true)
			if file_start >= 0 && file_end >= file_start {
				return c.sv_report(file_start, file_end, 'nonPrefixedFunction', {})
			}
		}
	}
	return c.sv_report(doc.lint_to_file(int(node_start(call)), false), doc.lint_to_file(int(node_end(call)),
		true), 'nonPrefixedFunction', {})
}
