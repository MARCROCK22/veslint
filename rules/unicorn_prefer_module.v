module rules

import estree
import time

// Port of the `unicorn/prefer-module` rule of eslint-plugin-unicorn 79.0.0 (it has no options),
// with its fix (of a "use strict" directive in a `.mjs` file) and its suggestions.

const upm_messages = {
	'error/use-strict-directive':             'Do not use "use strict" directive.'
	'error/global-return':                    '"return" should be used inside a function.'
	'error/identifier':                       'Do not use "{{name}}".'
	'suggestion/use-strict-directive':        'Remove "use strict" directive.'
	'suggestion/import-meta-dirname':         'Replace `__dirname` with `import.meta.dirname`.'
	'suggestion/import-meta-url-to-dirname':  'Replace `__dirname` with `…(import.meta.url)`.'
	'suggestion/import-meta-filename':        'Replace `__filename` with `import.meta.filename`.'
	'suggestion/import-meta-url-to-filename': 'Replace `__filename` with `…(import.meta.url)`.'
	'suggestion/import':                      'Switch to `import`.'
	'suggestion/export':                      'Switch to `export`.'
}

struct UpmSuggestion {
	message_id  string
	replacement string
	is_call     bool
}

const upm_suggestions = {
	'__dirname':  [
		UpmSuggestion{
			message_id:  'suggestion/import-meta-dirname'
			replacement: 'import.meta.dirname'
		},
		UpmSuggestion{
			message_id:  'suggestion/import-meta-url-to-dirname'
			replacement: 'path.dirname(url.fileURLToPath(import.meta.url))'
			is_call:     true
		},
	]
	'__filename': [
		UpmSuggestion{
			message_id:  'suggestion/import-meta-filename'
			replacement: 'import.meta.filename'
		},
		UpmSuggestion{
			message_id:  'suggestion/import-meta-url-to-filename'
			replacement: 'url.fileURLToPath(import.meta.url)'
			is_call:     true
		},
	]
}

const upm_common_js_globals = ['exports', 'require', 'module', '__filename', '__dirname']

fn (mut c Checker) lint_unicorn_prefer_module(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	filename := abs_path.to_lower()
	if filename.ends_with('.cjs') {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.expression_statement {
				if (t.string_of(node, .directive) or { continue }) != 'use strict' {
					continue
				}
				stats.checked++
				_, fix := c.merge_fixes([
					fix_remove_range(t.nodes[node].start, t.nodes[node].end),
					c.un_remove_spaces_after(t.nodes[node].end),
				]) or { continue }
				mut finding := Finding{
					stmt:       c.es_tree_position(t, node)
					message_id: 'error/use-strict-directive'
				}
				if filename.ends_with('.mjs') {
					finding = Finding{
						...finding
						has_fix: true
						fix:     fix
					}
				} else {
					finding = Finding{
						...finding
						suggestions: [
							Suggestion{
								message_id: 'suggestion/use-strict-directive'
								fix:        fix
							},
						]
					}
				}
				findings << finding
			}
			.return_statement {
				stats.checked++
				if upm_enclosing_function(t, node) < 0 {
					token := tokens.after(t.nodes[node].start, false) or { continue }
					findings << Finding{
						stmt:       c.position_range(token.start, token.end)
						message_id: 'error/global-return'
					}
				}
			}
			.identifier {
				stats.checked++
				if finding := c.upm_identifier(root, t, tokens, node) {
					findings << finding
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upm_enclosing_function ports getEnclosingFunction: the closest function that contains the node.
fn upm_enclosing_function(t &estree.EsTree, node int) int {
	for current := t.nodes[node].parent; current >= 0; current = t.nodes[current].parent {
		if unb_is_function(t, current) {
			return current
		}
	}
	return -1
}

// upm_is_global_reference is sourceCode.isGlobalReference: the key of a shorthand property and
// the exported name of a shorthand export specifier share their TypeScript node with the value,
// but only the value is a reference.
fn (mut c Checker) upm_is_global_reference(root C.vt_node, t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent >= 0 && ((t.typ(parent) == .property && t.node(parent, .key) or { -1 } == node
		&& t.node(parent, .value) or { -1 } != node)
		|| (t.typ(parent) == .export_specifier && t.node(parent, .exported) or { -1 } == node
		&& t.node(parent, .local) or { -1 } != node)
		|| (t.typ(parent) == .import_specifier && t.node(parent, .imported) or { -1 } == node
		&& t.node(parent, .local) or { -1 } != node)) {
		return false
	}
	ts := t.ts_node(node) or { return false }
	return c.es_is_global_reference(root, ts)
}

fn (mut c Checker) upm_identifier(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, node int) ?Finding {
	name := t.string_of(node, .name) or { return none }
	if name !in upm_common_js_globals || !c.upm_is_global_reference(root, t, node) {
		return none
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'error/identifier'
		data:       {
			'name': name
		}
	}
	match name {
		'__filename', '__dirname' {
			// TypeScript also requires parentheses before `import.meta` in a constructor callee
			// (typescript-estree always has the map of its nodes).
			in_new_callee := c.un_is_in_unparenthesized_new_callee(t, tokens, node)
			mut suggestions := []Suggestion{}
			for suggestion in upm_suggestions[name] {
				text := if in_new_callee {
					'(${suggestion.replacement})'
				} else {
					suggestion.replacement
				}
				suggestions << Suggestion{
					message_id: suggestion.message_id
					fix:        c.un_replace_reference_identifier(t, node, text)
				}
			}
			return Finding{
				...finding
				suggestions: suggestions
			}
		}
		'require' {
			if fixes := c.upm_fix_require_call(t, tokens, node) {
				return c.upm_with_suggestion(finding, 'suggestion/import', fixes)
			}
		}
		'exports' {
			if fixes := c.upm_fix_exports(t, tokens, node) {
				return c.upm_with_suggestion(finding, 'suggestion/export', fixes)
			}
		}
		'module' {
			if fixes := c.upm_fix_module_exports(t, tokens, node) {
				return c.upm_with_suggestion(finding, 'suggestion/export', fixes)
			}
		}
		else {}
	}
	return finding
}

fn (c &Checker) upm_with_suggestion(finding Finding, message_id string, fixes []Fix) Finding {
	_, fix := c.merge_fixes(fixes) or { return finding }
	return Finding{
		...finding
		suggestions: [
			Suggestion{
				message_id: message_id
				fix:        fix
			},
		]
	}
}

// upm_fix_require_call ports fixRequireCall: `require("foo")` and `const foo = require("foo")` at
// the top level become imports.
fn (c &Checker) upm_fix_require_call(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	require_call := t.nodes[node].parent
	if !un_is_call(t, require_call, names: ['require'], arguments_length: 1, optional: false)
		|| t.node(require_call, .callee) or { -1 } != node {
		return none
	}
	parent := t.nodes[require_call].parent
	callee := node
	source := (t.list(require_call, .arguments) or { return none })[0]
	source_value := un_static_string_value(t, source)?
	source_text := if raw := t.string_of(source, .raw) {
		raw
	} else {
		unb_escape_string(source_value, "'")
	}
	// A JSON module import needs `with {type: 'json'}`
	is_json := source_value.ends_with('.json')
	quote := source_text[..1]
	import_attributes := if is_json { ' with {type: ${quote}json${quote}}' } else { '' }
	call_tokens := c.un_call_tokens(t, tokens, require_call)?
	mut fixes := []Fix{}
	// `require("foo")`
	if parent >= 0 && t.typ(parent) == .expression_statement
		&& t.typ(t.nodes[parent].parent) == .program {
		fixes << fix_replace_range(t.nodes[source].start, t.nodes[source].end, source_text)
		fixes << fix_replace_range(t.nodes[callee].start, t.nodes[callee].end, 'import')
		fixes << fix_replace_range(call_tokens.opening.start, call_tokens.opening.end, ' ')
		fixes << fix_replace_range(call_tokens.closing.start, call_tokens.closing.end,
			import_attributes)
		for n in [callee, require_call, source] {
			fixes << c.un_remove_parentheses(t, tokens, n)
		}
		return fixes
	}
	// `const foo = require("foo")`, `const {foo} = require("foo")`
	if parent < 0 || t.typ(parent) != .variable_declarator
		|| t.node(parent, .init) or { -1 } != require_call {
		return none
	}
	id := t.node(parent, .id) or { return none }
	// `const foo: Foo = require("foo")` has no `import` form that keeps the annotation
	if _ := t.node(id, .type_annotation) {
		return none
	}
	properties := t.list(id, .properties) or { []int{} }
	if !(t.typ(id) == .identifier || (!is_json && t.typ(id) == .object_pattern
		&& properties.all(upm_is_plain_property(t, it)))) {
		return none
	}
	declaration := t.nodes[parent].parent
	declarations := t.list(declaration, .declarations) or { return none }
	if t.typ(declaration) != .variable_declaration
		|| (t.string_of(declaration, .kind) or { '' }) != 'const' || declarations.len != 1
		|| declarations[0] != parent || t.typ(t.nodes[declaration].parent) != .program {
		return none
	}
	fixes << fix_replace_range(t.nodes[source].start, t.nodes[source].end, source_text)
	// assertToken: ESLint stops with an error when these tokens are not the expected ones.
	const_token := tokens.after(t.nodes[declaration].start, false)?
	if c.token_text(const_token) != 'const' {
		return none
	}
	fixes << fix_replace_range(const_token.start, const_token.end, 'import')
	equal_token := tokens.after(t.nodes[id].end, false)?
	if !c.token_is(equal_token, '=') {
		return none
	}
	fixes << c.un_remove_spaces_after(t.nodes[id].end)
	fixes << c.un_remove_spaces_after(equal_token.end)
	fixes << fix_replace_range(equal_token.start, equal_token.end, ' from ')
	fixes << fix_remove_range(t.nodes[callee].start, t.nodes[callee].end)
	fixes << fix_remove_range(call_tokens.opening.start, call_tokens.opening.end)
	fixes << fix_replace_range(call_tokens.closing.start, call_tokens.closing.end, import_attributes)
	for n in [callee, require_call, source] {
		fixes << c.un_remove_parentheses(t, tokens, n)
	}
	if t.typ(id) == .identifier {
		return fixes
	}
	for property in properties {
		if t.flag(property, .shorthand) or { false } {
			continue
		}
		key := t.node(property, .key) or { return none }
		colon_token := tokens.after(t.nodes[key].end, false)?
		if !c.token_is(colon_token, ':') {
			return none
		}
		fixes << c.un_remove_spaces_after(t.nodes[key].end)
		fixes << c.un_remove_spaces_after(colon_token.end)
		fixes << fix_replace_range(colon_token.start, colon_token.end, ' as ')
	}
	return fixes
}

// upm_is_plain_property: a Property, not computed, with an Identifier key and value.
fn upm_is_plain_property(t &estree.EsTree, property int) bool {
	if t.typ(property) != .property || (t.flag(property, .computed) or { false }) {
		return false
	}
	key := t.node(property, .key) or { return false }
	value := t.node(property, .value) or { return false }
	return t.typ(value) == .identifier && t.typ(key) == .identifier
}

// upm_is_top_level_assignment ports isTopLevelAssignment: `node = …;` at the top level.
fn upm_is_top_level_assignment(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .assignment_expression
		|| (t.string_of(parent, .operator) or { '' }) != '='
		|| t.node(parent, .left) or { -1 } != node {
		return false
	}
	statement := t.nodes[parent].parent
	return statement >= 0 && t.typ(statement) == .expression_statement
		&& t.typ(t.nodes[statement].parent) == .program
}

// upm_is_plain_member: `node.<identifier>`, not optional nor computed.
fn upm_is_plain_member(t &estree.EsTree, node int) bool {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .member_expression || (t.flag(parent, .optional) or { false })
		|| (t.flag(parent, .computed) or { false }) || t.node(parent, .object) or { -1 } != node {
		return false
	}
	return t.typ(t.node(parent, .property) or { return false }) == .identifier
}

// upm_is_named_export ports isNamedExport: `node.foo = bar;` at the top level.
fn upm_is_named_export(t &estree.EsTree, node int) bool {
	if !upm_is_plain_member(t, node) {
		return false
	}
	member := t.nodes[node].parent
	if !upm_is_top_level_assignment(t, member) {
		return false
	}
	right := t.node(t.nodes[member].parent, .right) or { return false }
	return t.typ(right) == .identifier
}

// upm_fix_default_export ports fixDefaultExport: `exports = foo` becomes `export default foo`.
fn (c &Checker) upm_fix_default_export(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	mut fixes := []Fix{}
	fixes << fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'export default ')
	fixes << c.un_remove_spaces_after(t.nodes[node].end)
	equal_token := c.un_token_after_punctuator(tokens, t.nodes[node].end, '=')?
	fixes << fix_remove_range(equal_token.start, equal_token.end)
	fixes << c.un_remove_spaces_after(equal_token.end)
	for n in [t.nodes[node].parent, node] {
		fixes << c.un_remove_parentheses(t, tokens, n)
	}
	return fixes
}

// upm_fix_named_export ports fixNamedExport: `exports.foo = bar` becomes `export {bar as foo}`,
// unless a comment is in the assignment.
fn (c &Checker) upm_fix_named_export(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	member := t.nodes[node].parent
	assignment := t.nodes[member].parent
	if tokens.comments_inside(t.nodes[assignment].start, t.nodes[assignment].end).len > 0 {
		return none
	}
	exported := t.string_of(t.node(member, .property)?, .name)?
	local := t.string_of(t.node(assignment, .right)?, .name)?
	mut fixes := []Fix{}
	fixes << fix_replace_range(t.nodes[assignment].start, t.nodes[assignment].end,
		'export {${local} as ${exported}}')
	fixes << c.un_remove_parentheses(t, tokens, assignment)
	return fixes
}

// upm_fix_exports ports fixExports.
fn (c &Checker) upm_fix_exports(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	// `exports = bar`
	if upm_is_top_level_assignment(t, node) {
		return c.upm_fix_default_export(t, tokens, node)
	}
	// `exports.foo = bar`
	if upm_is_named_export(t, node) {
		return c.upm_fix_named_export(t, tokens, node)
	}
	return none
}

// upm_fix_module_exports ports fixModuleExports: the fixes of `module.exports`.
fn (c &Checker) upm_fix_module_exports(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	if upm_is_plain_member(t, node) {
		member := t.nodes[node].parent
		if (t.string_of(t.node(member, .property)?, .name) or { '' }) == 'exports' {
			return c.upm_fix_exports(t, tokens, member)
		}
	}
	return none
}
