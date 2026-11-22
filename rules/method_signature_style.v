module rules

import estree
import json2
import time

// Port of the `method-signature-style` rule of typescript-eslint 8.72.2, with its option
// ('property' or 'method'), its fixes and its suggestion (for a `readonly` property), on the
// ESTree.

const mss_messages = {
	'convertToMethodSignature': 'Convert to a method signature. This removes the `readonly` modifier, allowing the member to be reassigned.'
	'errorMethod':              'Shorthand method signature is forbidden. Use a function property instead.'
	'errorProperty':            'Function property signature is forbidden. Use a method shorthand instead.'
}

fn mss_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'property'
	}
	mode := options[0]
	if mode is string && mode in ['property', 'method'] {
		return mode
	}
	return error('the option of `${method_signature_style}` must be "property" or "method"')
}

// MssCtx is the file the rule looks at.
struct MssCtx {
	t      &estree.EsTree
	tokens &SourceTokens
	src    string
}

fn (x &MssCtx) text(node int) string {
	return x.src[x.t.nodes[node].start..x.t.nodes[node].end]
}

// key ports getMethodKey.
fn (x &MssCtx) key(node int) string {
	mut key := if k := x.t.node(node, .key) { x.text(k) } else { '' }
	if x.t.flag(node, .computed) or { false } {
		key = '[${key}]'
	}
	if x.t.flag(node, .optional) or { false } {
		key = '${key}?'
	}
	return key
}

// params ports getMethodParams.
fn (x &MssCtx) params(node int) string {
	mut params := '()'
	list := x.t.list(node, .params) or { []int{} }
	if list.len > 0 {
		mut opening := x.t.nodes[list[0]].start
		for {
			token := x.tokens.before(opening, false) or { break }
			opening = token.start
			if x.src[token.start..token.end] == '(' {
				break
			}
		}
		mut closing := x.t.nodes[list[list.len - 1]].end
		for {
			token := x.tokens.after(closing, false) or { break }
			closing = token.end
			if x.src[token.start..token.end] == ')' {
				break
			}
		}
		params = x.src[opening..closing]
	}
	if type_parameters := x.t.node(node, .type_parameters) {
		params = x.text(type_parameters) + params
	}
	return params
}

// return_type ports getMethodReturnType: `any` without a return type.
fn (x &MssCtx) return_type(node int) string {
	if return_type := x.t.node(node, .return_type) {
		if annotation := x.t.node(return_type, .type_annotation) {
			return x.text(annotation)
		}
	}
	return 'any'
}

// delimiter ports getDelimiter: the last token of the node, when it is `;` or `,`.
fn (x &MssCtx) delimiter(node int) string {
	last := x.tokens.before(x.t.nodes[node].end, false) or { return '' }
	text := x.src[last.start..last.end]
	return if text in [';', ','] { text } else { '' }
}

// mss_is_node_parent_module_declaration ports isNodeParentModuleDeclaration.
fn mss_is_node_parent_module_declaration(t &estree.EsTree, node int) bool {
	mut parent := t.nodes[node].parent
	for parent >= 0 {
		if t.typ(parent) == .ts_module_declaration {
			return true
		}
		if t.typ(parent) == .program {
			return false
		}
		parent = t.nodes[parent].parent
	}
	return false
}

// mss_has_this_type ports forEachChildESTree(node, child => child.type === TSThisType).
fn mss_has_this_type(t &estree.EsTree, node int) bool {
	if t.typ(node) == .ts_this_type {
		return true
	}
	for child in t.children(node) {
		if mss_has_this_type(t, child) {
			return true
		}
	}
	return false
}

// mss_return_type_references_this_type ports returnTypeReferencesThisType.
fn mss_return_type_references_this_type(t &estree.EsTree, node int) bool {
	return_type := t.node(node, .return_type) or { return false }
	annotation := t.node(return_type, .type_annotation) or { return false }
	return mss_has_this_type(t, annotation)
}

fn (mut c Checker) lint_method_signature_style(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mode := mss_options(c.rule_options(method_signature_style))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	x := MssCtx{
		t:      t
		tokens: c.source_tokens(root)
		src:    c.src
	}
	mut checked := 0
	for i, node in t.nodes {
		if mode == 'property' && node.typ == .ts_method_signature {
			if (t.string_of(i, .kind) or { '' }) != 'method' {
				continue
			}
			checked++
			findings << c.mss_check_method(x, i)!
		} else if mode == 'method' && node.typ == .ts_property_signature {
			annotation := t.node(i, .type_annotation) or { continue }
			type_node := t.node(annotation, .type_annotation) or { continue }
			if t.typ(type_node) != .ts_function_type {
				continue
			}
			checked++
			fix := fix_replace_range(node.start, node.end, '${x.key(i)}${x.params(type_node)}: ${x.return_type(type_node)}${x.delimiter(i)}')
			if t.flag(i, .readonly) or { false } {
				_, suggestion := c.suggestion('convertToMethodSignature', map[string]string{},
					[fix])!
				findings << Finding{
					stmt:        c.position_range(node.start, node.end)
					message_id:  'errorProperty'
					suggestions: [suggestion]
				}
				continue
			}
			findings << Finding{
				stmt:       c.position_range(node.start, node.end)
				message_id: 'errorProperty'
				has_fix:    true
				fix:        fix
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// mss_check_method is the listener of TSMethodSignature in mode 'property'.
fn (mut c Checker) mss_check_method(x &MssCtx, method int) !Finding {
	t := x.t
	position := c.position_range(t.nodes[method].start, t.nodes[method].end)
	skip_fix := mss_return_type_references_this_type(t, method)
	parent := t.nodes[method].parent
	members := if t.typ(parent) == .ts_interface_body {
		t.list(parent, .body) or { []int{} }
	} else {
		t.list(parent, .members) or { []int{} }
	}
	key := x.key(method)
	duplicates := members.filter(t.typ(it) == .ts_method_signature && it != method
		&& x.key(it) == key)
	if mss_is_node_parent_module_declaration(t, method) || skip_fix {
		return Finding{
			stmt:       position
			message_id: 'errorMethod'
		}
	}
	if duplicates.len > 0 {
		mut nodes := [method]
		nodes << duplicates
		// Sorted by their start (insertion sort: `sort` cannot read `t`).
		for k in 1 .. nodes.len {
			mut j := k
			for j > 0 && t.nodes[nodes[j]].start < t.nodes[nodes[j - 1]].start {
				nodes[j], nodes[j - 1] = nodes[j - 1], nodes[j]
				j--
			}
		}
		type_string := nodes.map('(${x.params(it)} => ${x.return_type(it)})').join(' & ')
		mut fixes := [
			fix_replace_range(t.nodes[method].start, t.nodes[method].end, '${key}: ${type_string}${x.delimiter(method)}'),
		]
		for node in duplicates {
			last := x.tokens.before(t.nodes[node].end, false) or { continue }
			next := x.tokens.after(last.end, false) or { continue }
			fixes << fix_remove_range(t.nodes[node].start, t.nodes[node].end)
			fixes << fix_replace_range(last.end, next.start, '')
		}
		return c.with_fixes(Finding{
			stmt:       position
			message_id: 'errorMethod'
		}, fixes)!
	}
	return Finding{
		stmt:       position
		message_id: 'errorMethod'
		has_fix:    true
		fix:        fix_replace_range(t.nodes[method].start, t.nodes[method].end, '${key}: ${x.params(method)} => ${x.return_type(method)}${x.delimiter(method)}')
	}
}
