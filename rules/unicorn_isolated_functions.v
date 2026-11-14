module rules

import esquery
import estree
import json2
import jsregexp
import time

// Port of the `unicorn/isolated-functions` rule of eslint-plugin-unicorn 79.0.0, with its options
// (`functions`, `selectors`, `comments` and `overrideGlobals`). The selectors run on the ESTree
// with the esquery module, as ESLint's traverser runs listeners.

const uisf_messages = {
	'externally-scoped-variable': 'Variable {{name}} not defined in scope of isolated function. Function is isolated because: {{reason}}.'
	'super':                      'Unexpected `super` in isolated function. Function is isolated because: {{reason}}.'
	'this-expression':            'Unexpected `this` in isolated function. Function is isolated because: {{reason}}.'
}

const uisf_function_types = ['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression']

// The own properties of Object.prototype, which ESLint's globals of an ecmaVersion have and the
// `globals` package's do not.
const uisf_object_prototype_names = ['constructor', 'hasOwnProperty', 'isPrototypeOf',
	'propertyIsEnumerable', 'toLocaleString', 'toString', 'valueOf']

struct UisfOptions {
	functions []string
	selectors []string
	comments  []string
	// The values of overrideGlobals: `true`, `false` or one of the strings.
	override_globals map[string]string
}

fn uisf_options(options []json2.Any) !UisfOptions {
	o := option_object(unicorn_isolated_functions, options, ['overrideGlobals', 'functions', 'selectors',
		'comments'])!
	mut override_globals := map[string]string{}
	if raw := o.values['overrideGlobals'] {
		// The schema checks the values of an object only: another value is accepted, and
		// `Object.hasOwn` finds in it its own properties, of which only the `length` of a string or
		// an array can be the name of a variable (a number: neither "off" nor writable). `null`
		// makes unicorn throw on the first reference it checks.
		mut value := raw
		if raw !is map[string]json2.Any {
			if raw is string || raw is []json2.Any {
				override_globals['length'] = 'number'
			}
			value = json2.Any(map[string]json2.Any{})
		}
		for name, global in value.as_map() {
			if global is bool {
				override_globals[name] = global.str()
			} else if global is string && global in ['readonly', 'writable', 'writeable', 'off'] {
				override_globals[name] = global
			} else {
				return error('option `overrideGlobals` of `${unicorn_isolated_functions}` must map names to true, false, "readonly", "writable", "writeable" or "off"')
			}
		}
	}
	selectors := o.string_list('selectors')!
	for selector in selectors {
		// An empty or blank selector does not reach ESLint's own selector check.
		if selector.trim_space() == '' {
			return error('option `selectors` of `${unicorn_isolated_functions}` must not have an empty selector')
		}
	}
	return UisfOptions{
		functions:        o.string_list('functions')!
		selectors:        selectors
		comments:         o.string_list('comments')!.map(uisf_js_lower(it))
		override_globals: override_globals
	}
}

// uisf_js_lower ports String.prototype.toLowerCase.
fn uisf_js_lower(s string) string {
	return stv_units_string(jsregexp.js_to_lower(utf16_units(s)))
}

fn (mut c Checker) lint_unicorn_isolated_functions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	opts := uisf_options(c.rule_options(unicorn_isolated_functions))!
	t := c.es_tree(root, abs_path) or { return findings }
	tree := c.scope_tree(root)
	tokens := c.un_tokens(t)
	// The listeners of each selector, in the order the rule adds them: -1 is the one of the
	// function types, k the one of the selector k. Listeners of the same selector are one.
	mut sources := []string{}
	mut listeners := [][]int{}
	for typ in uisf_function_types {
		sources << '${typ}:exit'
		listeners << [-1]
	}
	for k, selector in opts.selectors {
		source := '${selector}:exit'
		index := sources.index(source)
		if index >= 0 {
			listeners[index] << k
		} else {
			sources << source
			listeners << [k]
		}
	}
	mut checked := map[int]bool{}
	for m in esquery.run(t, sources)! {
		node := m.node
		for listener in listeners[m.selector] {
			stats.checked++
			reason := if listener < 0 {
				c.uisf_reason(t, tokens, node, opts) or { continue }
			} else {
				'matches selector ${js_json_stringify(json2.Any(opts.selectors[listener]))}'
			}
			if node in checked || t.typ(node).type_name() !in uisf_function_types {
				continue
			}
			checked[node] = true
			findings << c.uisf_problems(tree, t, node, reason, opts)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uisf_problems ports reportIsolatedFunctionProblems.
fn (mut c Checker) uisf_problems(tree &ScopeTree, t &estree.EsTree, node int, reason string, opts UisfOptions) []Finding {
	mut findings := []Finding{}
	// sourceCode.getScope(node): the innermost scope the function creates.
	ts := t.ts_node(node) or { return findings }
	scopes := tree.by_block[scope_block_key(ts)] or { return findings }
	if scopes.len == 0 {
		return findings
	}
	node_scope := scopes.last()
	// `through`: the references which could not be resolved in this scope.
	for r in tree.scopes[node_scope].through {
		reference := tree.references[r]
		identifier := c.un_reference_node(t, reference.identifier) or { continue }
		parent := t.nodes[identifier].parent
		if parent >= 0 && t.typ(parent) in [.ts_type_reference, .ts_type_query] {
			continue
		}
		name := t.string_of(identifier, .name) or { reference.name }
		mut problem_reason := reason
		if allowed := c.uisf_allowed_global_value(tree, r, name, opts) {
			if allowed != 'off' {
				if reference.is_read_only() {
					continue
				}
				if allowed in ['true', 'writable', 'writeable'] {
					continue
				}
				problem_reason += ' (global variable is not writable)'
			}
		}
		findings << Finding{
			stmt:       c.es_tree_position(t, identifier)
			message_id: 'externally-scoped-variable'
			data:       {
				'name':   name
				'reason': problem_reason
			}
		}
	}
	uisf_function_context_problems(t, node, node, mut findings, c, reason)
	return findings
}

// uisf_configured_global ports getConfiguredGlobal: the language option globals, then the
// builtin globals of the ecmaVersion as the `globals` package has them (all readonly).
fn (c &Checker) uisf_configured_global(name string) ?string {
	if value := c.language.globals[name] {
		return value
	}
	if uisf_is_builtin_global(c.language.ecma_version, name) {
		return 'false'
	}
	return none
}

// uisf_is_builtin_global: `name` is in `globals[es${ecmaVersion}] ?? globals.builtin` of the
// `globals` package (17.14.0), which has ESLint's globals of each version but the properties of
// Object.prototype, and puts AsyncDisposableStack, DisposableStack and SuppressedError in es2027
// (its `builtin`) and has no Temporal.
fn uisf_is_builtin_global(version int, name string) bool {
	if name in uisf_object_prototype_names || name == 'Temporal' {
		return false
	}
	known := version in scope_ecma_versions
	if !ecma_version_has_global(if known { version } else { scope_latest_ecma_version }, name) {
		return false
	}
	return !known || name !in ['AsyncDisposableStack', 'DisposableStack', 'SuppressedError']
}

// uisf_is_global_reference ports SourceCode#isGlobalReference: the reference is one of a variable
// of the global scope without definitions.
fn uisf_is_global_reference(tree &ScopeTree, r int, name string) bool {
	v := tree.scopes[0].set[name] or { return false }
	if tree.variables[v].defs.len > 0 {
		return false
	}
	return r in tree.variables[v].references
}

// uisf_allowed_global_value ports getAllowedGlobalValue; none is `undefined`.
fn (c &Checker) uisf_allowed_global_value(tree &ScopeTree, r int, name string, opts UisfOptions) ?string {
	resolved := tree.references[r].resolved
	if override := opts.override_globals[name] {
		if override == 'off' {
			return 'off'
		}
		if resolved >= 0 && !uisf_is_global_reference(tree, r, name) {
			return none
		}
		return override
	}
	configured := c.uisf_configured_global(name)
	if configured or { '' } == 'off' {
		return 'off'
	}
	if !uisf_is_global_reference(tree, r, name) {
		return none
	}
	if configured == none && !(resolved >= 0 && tree.variables[resolved].eslint_explicit_global) {
		return none
	}
	return if resolved >= 0 && tree.variables[resolved].writeable { 'writable' } else { 'readonly' }
}

// uisf_function_context_problems ports getFunctionContextProblems: `this` and `super` that refer
// to the function's context.
fn uisf_function_context_problems(t &estree.EsTree, node int, root int, mut findings []Finding, c &Checker, reason string) {
	typ := t.typ(node)
	if typ in [.super, .this_expression] {
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: if typ == .super { 'super' } else { 'this-expression' }
			data:       {
				'reason': reason
			}
		}
		return
	}
	if node != root {
		if typ in [.function_declaration, .function_expression] {
			return
		}
		if typ in [.class_declaration, .class_expression] {
			if super_class := t.node(node, .super_class) {
				uisf_function_context_problems(t, super_class, root, mut findings, c, reason)
			}
			body := t.node(node, .body) or { return }
			for element in t.list(body, .body) or { []int{} } {
				if t.flag(element, .computed) or { false } {
					if key := t.node(element, .key) {
						uisf_function_context_problems(t, key, root, mut findings, c,
							reason)
					}
				}
			}
			return
		}
	}
	for child in t.children(node) {
		uisf_function_context_problems(t, child, root, mut findings, c, reason)
	}
}

// uisf_can_comment_apply_to_parent ports canCommentApplyToParent.
fn uisf_can_comment_apply_to_parent(t &estree.EsTree, node int, parent int) bool {
	if parent < 0 {
		return false
	}
	if t.typ(parent) in [.variable_declarator, .variable_declaration, .export_named_declaration,
		.export_default_declaration] {
		return true
	}
	return t.typ(parent) in [.property, .method_definition]
		&& t.node(parent, .value) or { -1 } == node
}

// uisf_find_comment ports findComment: the value of the comment right before the node, or before
// the variable, export, property or method declaration it is part of.
fn (c &Checker) uisf_find_comment(t &estree.EsTree, tokens &SourceTokens, node int) ?string {
	mut previous := tokens.before(t.nodes[node].start, true)
	mut commentable := node
	for {
		if token := previous {
			if token.kind in [.line_comment, .block_comment] {
				break
			}
		}
		if !uisf_can_comment_apply_to_parent(t, commentable, t.nodes[commentable].parent) {
			break
		}
		commentable = t.nodes[commentable].parent
		previous = tokens.before(t.nodes[commentable].start, true)
	}
	token := previous?
	return match token.kind {
		.line_comment { c.src[token.start + 2..token.end] }
		.block_comment { c.src[token.start + 2..token.end - 2] }
		else { none }
	}
}

// uisf_strip_leading_stars is `.replace(/(?:\*\s*)*/, '')`: the `*`s (each with the white space
// after it) at the start.
fn uisf_strip_leading_stars(text string) string {
	mut runes := text.runes()
	mut i := 0
	for i < runes.len && runes[i] == `*` {
		i++
		for i < runes.len && is_js_space(runes[i]) {
			i++
		}
	}
	return runes[i..].string()
}

// uisf_reason ports reasonForBeingIsolatedFunction: why the function is isolated, none if it is
// not.
fn (c &Checker) uisf_reason(t &estree.EsTree, tokens &SourceTokens, node int, opts UisfOptions) ?string {
	if opts.comments.len > 0 {
		if comment := c.uisf_find_comment(t, tokens, node) {
			// JSDoc comments like `/** @isolated */` are parsed into `* @isolated`.
			previous := uisf_js_lower(js_trim(uisf_strip_leading_stars(comment)))
			for candidate in opts.comments {
				if previous == candidate || previous.starts_with('${candidate} - ')
					|| previous.starts_with('${candidate} -- ') {
					return 'follows comment ${js_json_stringify(json2.Any(candidate))}'
				}
			}
		}
	}
	parent := t.nodes[node].parent
	if opts.functions.len > 0 && parent >= 0 && t.typ(parent) == .call_expression
		&& node in (t.list(parent, .arguments) or { []int{} }) {
		callee := t.node(parent, .callee) or { -1 }
		if callee >= 0 && t.typ(callee) == .identifier {
			name := t.string_of(callee, .name) or { '' }
			if name in opts.functions {
				return 'callee of function named ${js_json_stringify(json2.Any(name))}'
			}
		}
	}
	if reason := uisf_default_argument_call_reason(t, node) {
		return reason
	}
	return uisf_execute_script_property_reason(t, node)
}

// uisf_default_argument_call_reason ports getDefaultArgumentCallReason.
fn uisf_default_argument_call_reason(t &estree.EsTree, node int) ?string {
	parent := t.nodes[node].parent
	if parent < 0 || t.typ(parent) != .call_expression {
		return none
	}
	arguments := t.list(parent, .arguments) or { return none }
	if arguments.len == 0 || arguments[0] != node {
		return none
	}
	if un_is_method_call(t, parent, objects: ['browser'], methods: ['execute']) {
		return 'callee of method named "browser.execute"'
	}
	if un_is_method_call(t, parent, objects: ['page'], methods: ['evaluate']) {
		return 'callee of method named "page.evaluate"'
	}
	return none
}

// uisf_object_property_name ports getObjectPropertyName.
fn uisf_object_property_name(t &estree.EsTree, node int) ?string {
	key := t.node(node, .key)?
	if !(t.flag(node, .computed) or { false }) && t.typ(key) == .identifier {
		return t.string_of(key, .name)
	}
	return un_static_string_value(t, key)
}

// uisf_execute_script_property_reason ports getExecuteScriptPropertyReason: the `func` of
// `chrome.scripting.executeScript({func})` or `browser.scripting.executeScript({func})`.
fn uisf_execute_script_property_reason(t &estree.EsTree, node int) ?string {
	property := t.nodes[node].parent
	if property < 0 || t.typ(property) != .property || t.string_of(property, .kind) or { '' } != 'init' {
		return none
	}
	if uisf_object_property_name(t, property) or { return none } != 'func' {
		return none
	}
	object := t.nodes[property].parent
	if object < 0 || t.typ(object) != .object_expression {
		return none
	}
	call := t.nodes[object].parent
	if call < 0 || t.typ(call) != .call_expression {
		return none
	}
	arguments := t.list(call, .arguments) or { return none }
	if arguments.len == 0 || arguments[0] != object {
		return none
	}
	// getScriptingExecuteScriptObjectName
	if !un_is_method_call(t, call, methods: ['executeScript']) {
		return none
	}
	callee_object := t.node(t.node(call, .callee)?, .object)?
	if !un_is_member(t, callee_object, objects: ['browser', 'chrome'], properties: ['scripting']) {
		return none
	}
	name := t.string_of(t.node(callee_object, .object)?, .name)?
	return 'property "func" passed to "${name}.scripting.executeScript"'
}
