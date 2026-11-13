module rules

import time
import treesitter { children, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `prefer-function-type` rule of typescript-eslint 8.62.0 (it has no options), with
// its fix.

const pft_messages = {
	'functionTypeOverCallableType':          '{{ literalOrInterface }} only has a call signature, you should use a function type instead.'
	'unexpectedThisOnFunctionOnlyInterface': "`this` refers to the function type '{{ interfaceName }}', did you intend to use a generic `this` parameter like `<Self>(this: Self, ...) => Self` instead?"
}

fn (mut c Checker) lint_prefer_function_type(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['interface_declaration', 'object_type'], []) {
		if node_kind(node) == 'interface_declaration' {
			// An interface without a supertype other than `Function`, with a single member.
			body := node_field(node, 'body') or { continue }
			members := named_children(body)
			if c.pft_has_one_supertype(node) || members.len != 1 {
				continue
			}
			checked++
			c.pft_check_member(members[0], node, pft_this_types(node), mut findings)!
			continue
		}
		// `TSTypeLiteral[members.length = 1]` (a mapped type is a TSMappedType).
		if _ := scope_mapped_clause(node) {
			continue
		}
		members := named_children(node)
		if members.len != 1 {
			continue
		}
		checked++
		c.pft_check_member(members[0], node, []C.TSNode{}, mut findings)!
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// pft_has_one_supertype ports hasOneSupertype: the interface extends something other than
// `Function` alone.
fn (c &Checker) pft_has_one_supertype(node C.TSNode) bool {
	mut heritage := []C.TSNode{}
	for clause in named_children(node) {
		if node_kind(clause) == 'extends_type_clause' {
			heritage << named_children(clause)
		}
	}
	if heritage.len == 0 {
		return false
	}
	if heritage.len != 1 {
		return true
	}
	expression := if node_kind(heritage[0]) == 'generic_type' {
		node_field(heritage[0], 'name') or { heritage[0] }
	} else {
		heritage[0]
	}
	return node_kind(expression) != 'type_identifier'
		|| c.identifier_name(expression) != 'Function'
}

// pft_check_member ports checkMember for the single member of an interface or of a type literal
// (`node`): a call or construct signature with a return type is reported, at the first `this`
// type of the interface if it has one, else with the fix that turns the type into a function
// type.
fn (mut c Checker) pft_check_member(member C.TSNode, node C.TSNode, this_types []C.TSNode, mut findings []Finding) ! {
	kind := node_kind(member)
	if kind !in ['call_signature', 'construct_signature'] {
		return
	}
	return_type := node_field(member, if kind == 'call_signature' { 'return_type' } else { 'type' }) or {
		return
	}
	is_interface := node_kind(node) == 'interface_declaration'
	if is_interface && this_types.len > 0 {
		name := node_field(node, 'name') or { return }
		findings << Finding{
			stmt:       position_of(this_types[0])
			message_id: 'unexpectedThisOnFunctionOnlyInterface'
			data:       {
				'interfaceName': c.identifier_name(name)
			}
		}
		return
	}
	finding := Finding{
		stmt:       c.position_range(node_start(member), c.es_member_end(member))
		message_id: 'functionTypeOverCallableType'
		data:       {
			'literalOrInterface': if is_interface { 'Interface' } else { 'Type literal' }
		}
	}
	// The ESTree interface starts at its `declare`, and its parent is the export around it.
	mut start := node_start(node)
	mut export := ?C.TSNode(none)
	mut export_default := false
	if is_interface {
		mut parent := node_parent(node) or { node }
		if node_kind(parent) == 'ambient_declaration' {
			start = node_start(parent)
			parent = node_parent(parent) or { parent }
		}
		if node_kind(parent) == 'export_statement' {
			export_default = has_child_kind(parent, 'default')
			if !export_default {
				export = parent
			}
		}
	}
	if export_default {
		findings << finding
		return
	}
	findings << c.with_fixes(finding, c.pft_fixes(member, return_type, node, start, export))!
}

// pft_fixes: the type becomes `<member> =>`, the colon of the return type replaced, without its
// `;` and in parentheses where a union, an intersection or an array holds it; an interface
// becomes a type alias. The comments around the member go before the export of the interface,
// or before the new text.
fn (mut c Checker) pft_fixes(member C.TSNode, return_type C.TSNode, node C.TSNode, start int, export ?C.TSNode) []Fix {
	member_start := node_start(member)
	member_end := c.pft_member_end(member)
	colon := node_start(return_type) - member_start
	text := c.src[member_start..member_end]
	mut suggestion := '${text[..colon]} =>${text[colon + 1..]}'
	last_char := if suggestion.ends_with(';') { ';' } else { '' }
	if last_char != '' {
		suggestion = suggestion[..suggestion.len - 1]
	}
	is_interface := node_kind(node) == 'interface_declaration'
	if !is_interface {
		if parent := type_parent(node) {
			if node_kind(parent) in ['union_type', 'intersection_type', 'array_type'] {
				suggestion = '(${suggestion})'
			}
		}
	} else if name := node_field(node, 'name') {
		if parameters := node_field(node, 'type_parameters') {
			suggestion = 'type ${c.src[node_start(name)..node_end(parameters)]} = ${suggestion}${last_char}'
		} else {
			suggestion = 'type ${c.identifier_name(name)} = ${suggestion}${last_char}'
		}
	}
	tokens := c.source_tokens(member)
	mut comments := tokens.comments_before(member_start).clone()
	comments << tokens.comments_after(member_end)
	mut fixes := []Fix{}
	mut exported := false
	if is_interface {
		if statement := export {
			exported = true
			fixes << fix_insert_at(node_start(statement), comments.map('${c.token_text(it)}\n').join(''))
		}
	}
	if !exported {
		for comment in comments {
			separator := if pft_same_line(c.src, comment.start, member_start) { ' ' } else { '\n' }
			suggestion = '${c.token_text(comment)}${separator}${suggestion}'
		}
	}
	fixes << fix_replace_range(start, c.tokens.last_end(node_end(node)), suggestion)
	return fixes
}

// pft_member_end is where a member ends in ESTree: TypeScript gives it the `,` or `;` that
// follows it.
fn (mut c Checker) pft_member_end(member C.TSNode) int {
	end := c.tokens.last_end(node_end(member))
	if next := c.source_tokens(member).after(end, false) {
		if c.token_is(next, ',') || c.token_is(next, ';') {
			return next.end
		}
	}
	return end
}

// pft_this_types are the TSThisType nodes of an interface that are not inside a TSTypeLiteral,
// in order: `this` types, and the `this` of a type predicate or an `asserts`.
fn pft_this_types(iface C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	pft_collect_this(iface, mut out)
	return out
}

fn pft_collect_this(n C.TSNode, mut out []C.TSNode) {
	for child in children(n) {
		match node_kind(child) {
			'object_type' {
				if _ := scope_mapped_clause(child) {
					pft_collect_this(child, mut out)
				}
			}
			'this_type' {
				out << child
			}
			'this' {
				if node_kind(n) in ['type_predicate', 'asserts'] && C.ts_node_is_named(n) {
					out << child
				}
			}
			else {
				pft_collect_this(child, mut out)
			}
		}
	}
}

// pft_same_line: no line break between the two offsets (ESLint's lines).
fn pft_same_line(src string, a int, b int) bool {
	lo, hi := if a < b { a, b } else { b, a }
	for i in lo .. hi {
		ch := src[i]
		if ch == `\n` || ch == `\r` {
			return false
		}
		if ch == 0xe2 && i + 2 < src.len && src[i + 1] == 0x80 && src[i + 2] in [
			u8(0xa8),
			0xa9,
		] {
			return false
		}
	}
	return true
}
