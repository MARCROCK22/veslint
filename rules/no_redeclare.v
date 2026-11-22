module rules

import estree
import json2
import time
import treesitter { node_kind, node_start }

// Port of the `no-redeclare` rule of typescript-eslint 8.72.2 (its own version of ESLint's rule),
// with its options `builtinGlobals` and `ignoreDeclarationMerge`: the variables of the scopes of the
// Program (global and module), of functions, blocks, loops and switches, with their definitions
// from the scope tree and the ESTree types of their parents.

const tsnr_messages = {
	'redeclared':          "'{{id}}' is already defined."
	'redeclaredAsBuiltin': "'{{id}}' is already defined as a built-in global variable."
	'redeclaredBySyntax':  "'{{id}}' is already defined by a variable declaration."
}

struct TsnrOptions {
	builtin_globals          bool
	ignore_declaration_merge bool
}

fn tsnr_options(options []json2.Any) !TsnrOptions {
	o := option_object(no_redeclare, options, ['builtinGlobals', 'ignoreDeclarationMerge'])!
	return TsnrOptions{
		builtin_globals:          o.bool_value('builtinGlobals')!
		ignore_declaration_merge: o.bool_value('ignoreDeclarationMerge')!
	}
}

// TsnrDeclaration is what iterateDeclarations yields: a built-in global (no place), a
// `/* global */` comment or an identifier, with the place of a report.
struct TsnrDeclaration {
	kind  string // 'builtin', 'comment' or 'syntax'
	start int
	end   int
}

// TsnrIdentifier is an identifier of a variable and the ESTree type of its parent.
struct TsnrIdentifier {
	start  int
	end    int
	parent estree.NodeType
}

fn (mut c Checker) lint_no_redeclare(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := tsnr_options(c.rule_options(no_redeclare))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	// The ESTree Identifiers by their start.
	mut identifiers := map[int]int{}
	for i, node in t.nodes {
		if node.typ == .identifier {
			identifiers[node.start] = i
		}
	}
	mut checked := 0
	for s in 0 .. tree.scopes.len {
		if !c.tsnr_is_checked_scope(t, tree, s) {
			continue
		}
		for v in tree.scopes[s].variables {
			checked++
			declarations := c.tsnr_declarations(root, t, tree, identifiers, v, o)
			if declarations.len < 2 {
				continue
			}
			first := declarations[0]
			detail := if first.kind == 'builtin' {
				'redeclaredAsBuiltin'
			} else {
				'redeclaredBySyntax'
			}
			for d in declarations[1..] {
				if d.kind == 'builtin' {
					continue
				}
				findings << Finding{
					stmt:       c.position_range(d.start, d.end)
					message_id: if d.kind == first.kind { 'redeclared' } else { detail }
					data:       {
						'id': tree.variables[v].name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// tsnr_is_checked_scope: the scope is one the rule looks at: the global scope, the scope whose
// block is the Program right inside it (a module), or a scope whose block is an
// ArrowFunctionExpression, BlockStatement, ForInStatement, ForOfStatement, ForStatement,
// FunctionDeclaration, FunctionExpression or SwitchStatement (checkForBlock).
fn (mut c Checker) tsnr_is_checked_scope(t &estree.EsTree, tree &ScopeTree, s int) bool {
	scope := tree.scopes[s]
	if s == 0 {
		return true
	}
	if node_kind(scope.block) == 'program' {
		// A .svelte file: the Program's scope is the global one (svelte-eslint-parser's
		// acquire), and the module scope's block is not the global scope's.
		if c.is_svelte() {
			return false
		}
		return scope.upper == 0 && tree.scopes[0].children.len > 0 && tree.scopes[0].children[0] == s
	}
	match scope.kind {
		.function {
			index := c.es_index_of(t, scope.block) or { return false }
			return t.typ(index) in [.arrow_function_expression, .function_declaration,
				.function_expression]
		}
		.block {
			index := c.es_index_of(t, scope.block) or { return false }
			return t.typ(index) == .block_statement
		}
		.for_statement, .switch_statement {
			return true
		}
		else {
			return false
		}
	}
}

// tsnr_declarations ports iterateDeclarations.
fn (mut c Checker) tsnr_declarations(root C.vt_node, t &estree.EsTree, tree &ScopeTree, identifiers map[int]int, v int, o TsnrOptions) []TsnrDeclaration {
	variable := tree.variables[v]
	mut out := []TsnrDeclaration{}
	if o.builtin_globals && variable.eslint_implicit_global_setting in ['readonly', 'writable'] {
		out << TsnrDeclaration{
			kind: 'builtin'
		}
	}
	if variable.eslint_explicit_global {
		for start, end in c.tsnr_global_comment_locations(root, variable.name) {
			out << TsnrDeclaration{
				kind:  'comment'
				start: start
				end:   end
			}
		}
	}
	mut ids := []TsnrIdentifier{}
	for identifier in variable.identifiers {
		index := identifiers[node_start(identifier)] or { continue }
		parent := t.nodes[index].parent
		parent_type := if parent >= 0 { t.typ(parent) } else { estree.NodeType.program }
		// Function declarations without a body are overloads for TypeScript.
		if parent_type == .ts_declare_function {
			continue
		}
		ids << TsnrIdentifier{
			start:  t.nodes[index].start
			end:    t.nodes[index].end
			parent: parent_type
		}
	}
	if o.ignore_declaration_merge && ids.len > 1 {
		// Interfaces, or namespaces, merging.
		if ids.all(it.parent == .ts_interface_declaration) || ids.all(it.parent == .ts_module_declaration) {
			return out
		}
		// A class, a function or an enum merged with interfaces or namespaces (with a class) or
		// namespaces: more than one of them is reported.
		for merged, allowed in {
			estree.NodeType.class_declaration: [estree.NodeType.class_declaration,
				.ts_interface_declaration, .ts_module_declaration]
			.function_declaration:             [estree.NodeType.function_declaration,
				.ts_module_declaration]
			.ts_enum_declaration:              [estree.NodeType.ts_enum_declaration,
				.ts_module_declaration]
		} {
			if ids.all(it.parent in allowed) {
				declarations := ids.filter(it.parent == merged)
				if declarations.len == 1 {
					return out
				}
				for id in declarations {
					out << TsnrDeclaration{
						kind:  'syntax'
						start: id.start
						end:   id.end
					}
				}
				return out
			}
		}
	}
	for id in ids {
		out << TsnrDeclaration{
			kind:  'syntax'
			start: id.start
			end:   id.end
		}
	}
	return out
}

// tsnr_global_comment_locations ports getNameLocationInGlobalDirectiveComment for each
// `/* global */` comment that declares the name (eslintExplicitGlobalComments), in order: the
// name after `global`, preceded by a space or a comma and followed by the end, a space, a comma or
// a colon (as many UTF-16 units as the name); without it, the first unit of the comment's value.
fn (mut c Checker) tsnr_global_comment_locations(root C.vt_node, name string) map[int]int {
	mut out := map[int]int{}
	for comment in c.source_tokens(root).comments {
		if comment.kind != .block_comment {
			continue
		}
		value := c.src[comment.start + 2..comment.end - 2]
		label, directive_value, _ := parse_directive(value) or { continue }
		if label !in ['global', 'globals'] {
			continue
		}
		mut named := false
		for entry in global_entries(directive_value) {
			valid := !entry.has_value
				|| entry.value in ['off', 'true', 'writeable', 'writable', 'false', 'readable',
					'readonly']
			if valid && entry.name == name {
				named = true
				break
			}
		}
		if !named {
			continue
		}
		base := comment.start + 2
		mut start := base
		mut length := 1
		from := (value.index('global') or { -6 }) + 6
		mut i := from
		for i < value.len {
			separator := utf8_char_len(value[i])
			character := value[i..i + separator].runes()[0]
			if character == `,` || is_js_space(character) {
				rest := value[i + separator..]
				if rest.starts_with(name) {
					after := rest[name.len..]
					mut ends := after == ''
					if !ends {
						next := after[..utf8_char_len(after[0])].runes()[0]
						ends = next == `,` || next == `:` || is_js_space(next)
					}
					if ends {
						start = base + i + separator
						length = utf16_units(name).len
						break
					}
				}
			}
			i += separator
		}
		out[start] = tsid_advance_units(c.src, start, length)
	}
	return out
}
