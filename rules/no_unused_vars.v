module rules

import json2
import offsets
import time
import treesitter { has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-unused-vars` rule of typescript-eslint 8.62.0, with its options (`'all'`,
// `'local'`, or an object with `args`, `argsIgnorePattern`, `caughtErrors`,
// `caughtErrorsIgnorePattern`, `destructuredArrayIgnorePattern`, `enableAutofixRemoval`,
// `ignoreClassWithStaticInitBlock`, `ignoreRestSiblings`, `ignoreUsingDeclarations`,
// `reportUsedIgnorePattern`, `vars` and `varsIgnorePattern`), its suggestions and its fixes (for
// imports). It is built on unused_variables.v (util/collectUnusedVariables); the patterns are
// regular expressions with the `u` flag, matched by regexp_match.v.

const nuv_messages = {
	'removeUnusedImportDeclaration': 'Remove unused import declaration.'
	'removeUnusedVar':               'Remove unused variable "{{varName}}".'
	'unusedVar':                     "'{{varName}}' is {{action}} but never used{{additional}}."
	'usedIgnoredVar':                "'{{varName}}' is marked as ignored but is used{{additional}}."
	'usedOnlyAsType':                "'{{varName}}' is {{action}} but only used as a type{{additional}}."
}

// NuvPattern is an ignore pattern: `new RegExp(pattern, 'u')`, when the option is a non-empty text.
struct NuvPattern {
	has     bool
	program RegexpProgram
	text    string // RegExp.prototype.toString()
}

struct NuvOptions {
	vars_local                          bool
	args                                string = 'after-used'
	caught_errors_none                  bool
	ignore_rest_siblings                bool
	ignore_using_declarations           bool
	ignore_class_with_static_init_block bool
	report_used_ignore_pattern          bool
	autofix_imports                     bool
	vars_pattern                        NuvPattern
	args_pattern                        NuvPattern
	caught_errors_pattern               NuvPattern
	destructured_array_pattern          NuvPattern
}

fn nuv_options(options []json2.Any) !NuvOptions {
	if options.len == 0 {
		return NuvOptions{}
	}
	first := options[0]
	if first is string {
		if first !in ['all', 'local'] {
			return error("the option of `${no_unused_vars}` must be 'all', 'local' or an object")
		}
		return NuvOptions{
			vars_local: first == 'local'
		}
	}
	o := option_object(no_unused_vars, options, ['args', 'argsIgnorePattern', 'caughtErrors',
		'caughtErrorsIgnorePattern', 'destructuredArrayIgnorePattern', 'enableAutofixRemoval',
		'ignoreClassWithStaticInitBlock', 'ignoreRestSiblings', 'ignoreUsingDeclarations',
		'reportUsedIgnorePattern', 'vars', 'varsIgnorePattern'])!
	mut autofix_imports := false
	if removal := o.values['enableAutofixRemoval'] {
		if removal !is map[string]json2.Any {
			return error('option `enableAutofixRemoval` of `${no_unused_vars}` must be an object')
		}
		inner := option_object(no_unused_vars, [removal], ['imports'])!
		autofix_imports = inner.bool_value('imports')!
	}
	args := o.string_value('args', ['all', 'after-used', 'none', ''])!
	return NuvOptions{
		vars_local:                          o.string_value('vars', ['all', 'local', ''])! == 'local'
		args:                                if args == '' { 'after-used' } else { args }
		caught_errors_none:                  o.string_value('caughtErrors', ['all', 'none', ''])! == 'none'
		ignore_rest_siblings:                o.bool_value('ignoreRestSiblings')!
		ignore_using_declarations:           o.bool_value('ignoreUsingDeclarations')!
		ignore_class_with_static_init_block: o.bool_value('ignoreClassWithStaticInitBlock')!
		report_used_ignore_pattern:          o.bool_value('reportUsedIgnorePattern')!
		autofix_imports:                     autofix_imports
		vars_pattern:                        nuv_pattern(o, 'varsIgnorePattern')!
		args_pattern:                        nuv_pattern(o, 'argsIgnorePattern')!
		caught_errors_pattern:               nuv_pattern(o, 'caughtErrorsIgnorePattern')!
		destructured_array_pattern:          nuv_pattern(o, 'destructuredArrayIgnorePattern')!
	}
}

// nuv_pattern compiles an ignore pattern; an empty text is no pattern (`if (option.x)`).
fn nuv_pattern(o OptionObject, key string) !NuvPattern {
	value := o.values[key] or { return NuvPattern{} }
	if value !is string {
		return error('option `${key}` of `${no_unused_vars}` must be a text')
	}
	pattern := value as string
	if pattern == '' {
		return NuvPattern{}
	}
	program := regexp_compile(pattern) or {
		return error('`${no_unused_vars}`: veslint cannot use the regular expression `${pattern}`: ${err.msg()}')
	}
	return NuvPattern{
		has:     true
		program: program
		text:    nuv_regexp_text(pattern)
	}
}

// nuv_regexp_text is RegExp.prototype.toString() of `new RegExp(pattern, 'u')`, as V8 writes its
// source: a `/` outside a class is escaped, a line terminator becomes its escape (a backslash
// before one is dropped), and an empty source is `(?:)`.
fn nuv_regexp_text(pattern string) string {
	runes := pattern.runes()
	mut out := []rune{}
	mut in_class := false
	mut i := 0
	for i < runes.len {
		ch := runes[i]
		if ch == `\\` {
			if i + 1 < runes.len && runes[i + 1] in [`\n`, `\r`, rune(0x2028), rune(0x2029)] {
				i++
				continue
			}
			out << ch
			i++
			if i < runes.len {
				out << runes[i]
				i++
			}
			continue
		}
		match ch {
			`/` {
				if !in_class {
					out << `\\`
				}
				out << ch
			}
			`[` {
				in_class = true
				out << ch
			}
			`]` {
				in_class = false
				out << ch
			}
			`\n` {
				out << '\\n'.runes()
			}
			`\r` {
				out << '\\r'.runes()
			}
			rune(0x2028) {
				out << '\\u2028'.runes()
			}
			rune(0x2029) {
				out << '\\u2029'.runes()
			}
			else {
				out << ch
			}
		}
		i++
	}
	source := if out.len == 0 { '(?:)' } else { out.string() }
	return '/${source}/u'
}

// nuv_test is `pattern.test(name)`.
fn nuv_test(pattern NuvPattern, name string) !bool {
	if !pattern.has {
		return false
	}
	return regexp_test(pattern.program, name)
}

// NuvType is the VariableType of a definition, as far as the messages and the fixers tell them
// apart.
enum NuvType {
	array_destructure
	catch_clause
	parameter
	import_binding
	other
}

// NuvState is what the rule keeps while it reports: the scope tree, the variables marked as
// used (`eslintUsed`) and the ones reported so far (reportedUnusedVariables).
struct NuvState {
	tree &ScopeTree = unsafe { nil }
	o    NuvOptions
mut:
	eslint_used map[int]bool
	reported    map[int]bool
	findings    []Finding
}

fn (mut c Checker) lint_no_unused_vars(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nuv_options(c.rule_options(no_unused_vars))!
	tree := c.scope_tree(root)
	// The selectors of declarations that are ambiently exported mark them as used during the
	// traversal; collectVariables runs at Program:exit, so it sees them.
	ambient := c.nuv_ambient_marks(root, tree, abs_path)
	marked := c.unused_marked(root, tree)
	unused := c.unused_variables(root, tree)
	mut state := NuvState{
		tree: tree
		o:    o
	}
	mut unused_list := []int{}
	mut used_list := []int{}
	for scope in tree.scopes {
		if scope.kind == .function_expression_name {
			continue
		}
		for v in scope.variables {
			variable := tree.variables[v]
			if variable.lib {
				continue
			}
			if marked[v] || variable.eslint_used || ambient[v] {
				state.eslint_used[v] = true
			}
			if unused[v] && !ambient[v] {
				unused_list << v
			} else {
				used_list << v
			}
		}
	}
	mut checked := 0
	mut reports := []int{}
	for v in unused_list {
		checked++
		if c.nuv_keep(mut state, v, false)! {
			reports << v
		}
	}
	for v in used_list {
		checked++
		c.nuv_keep(mut state, v, true)!
	}
	// Program:exit
	for v in reports {
		variable := tree.variables[v]
		if variable.defs.len > 0 {
			only_as_type := variable.references.any(inside_type_query(tree.references[it].identifier)
				|| unused_in_type_predicate(tree.references[it].identifier))
			if only_as_type && variable.defs.any(it.kind == .import_binding) {
				continue
			}
			message_id := if only_as_type { 'usedOnlyAsType' } else { 'unusedVar' }
			data := if variable.references.any(tree.references[it].write) {
				state.nuv_message_data(v, 'assigned a value')
			} else {
				state.nuv_message_data(v, 'defined')
			}
			c.nuv_report(mut state, v, message_id, data)!
		} else if variable.eslint_explicit_global {
			// The first `/* global */` comment that names it.
			offset := c.nuv_global_comment_location(root, variable.name) or { continue }
			state.findings << Finding{
				stmt:       c.position_at(offset)
				message_id: 'unusedVar'
				data:       {
					'action':     'defined'
					'additional': ''
					'varName':    variable.name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return state.findings
}

// nuv_type ports defToVariableType for what the rule needs of it.
fn (s &NuvState) nuv_type(definition ScopeDefinition) NuvType {
	if s.o.destructured_array_pattern.has && nuv_parent_is_array_pattern(definition.name, false) {
		return .array_destructure
	}
	return match definition.kind {
		.catch_clause { .catch_clause }
		.parameter { .parameter }
		.import_binding { .import_binding }
		else { .other }
	}
}

// nuv_description ports getVariableDescription: the pattern of the type, and how its message
// calls the variables.
fn (s &NuvState) nuv_description(kind NuvType) (NuvPattern, string) {
	return match kind {
		.array_destructure { s.o.destructured_array_pattern, 'elements of array destructuring' }
		.catch_clause { s.o.caught_errors_pattern, 'caught errors' }
		.parameter { s.o.args_pattern, 'args' }
		else { s.o.vars_pattern, 'vars' }
	}
}

// nuv_message_data ports getDefinedMessageData and getAssignedMessageData.
fn (s &NuvState) nuv_message_data(v int, action string) map[string]string {
	variable := s.tree.variables[v]
	mut additional := ''
	if variable.defs.len > 0 {
		pattern, description := s.nuv_description(s.nuv_type(variable.defs[0]))
		if pattern.has {
			additional = '. Allowed unused ${description} must match ${pattern.text}'
		}
	}
	return {
		'action':     action
		'additional': additional
		'varName':    variable.name
	}
}

// nuv_used_ignored_data ports getUsedIgnoredMessageData.
fn (s &NuvState) nuv_used_ignored_data(v int, kind NuvType) map[string]string {
	pattern, description := s.nuv_description(kind)
	mut additional := ''
	if pattern.has {
		additional = '. Used ${description} must not match ${pattern.text}'
	}
	return {
		'additional': additional
		'varName':    s.tree.variables[v].name
	}
}

// nuv_keep ports the loop of the rule's collectUnusedVariables for one variable: whether it is one
// to report as unused (never for a used one), after reporting a used variable that an ignore
// pattern names when reportUsedIgnorePattern asks for it.
fn (mut c Checker) nuv_keep(mut s NuvState, v int, used bool) !bool {
	tree := s.tree
	variable := tree.variables[v]
	o := s.o
	// Explicit global variables have no definitions.
	if variable.defs.len == 0 {
		return !used
	}
	definition := variable.defs[0]
	if tree.scopes[variable.scope].kind == .global && o.vars_local {
		return false
	}
	name := definition.name
	is_identifier := node_kind(name) != 'string'
	name_text := variable.name
	// Elements of array destructuring.
	in_array_pattern := nuv_parent_is_array_pattern(name, false)
		|| variable.references.any(nuv_parent_is_array_pattern(tree.references[it].identifier, tree.references[it].write))
	if in_array_pattern && is_identifier && nuv_test(o.destructured_array_pattern, name_text)! {
		if o.report_used_ignore_pattern && used {
			c.nuv_report(mut s, v, 'usedIgnoredVar', s.nuv_used_ignored_data(v, .array_destructure))!
		}
		return false
	}
	if definition.kind == .class_name && o.ignore_class_with_static_init_block {
		if body := node_field(definition.node, 'body') {
			if has_child_kind(body, 'class_static_block') {
				return false
			}
		}
	}
	if definition.kind == .catch_clause {
		if o.caught_errors_none {
			return false
		}
		if nuv_test(o.caught_errors_pattern, name_text)! {
			if o.report_used_ignore_pattern && used {
				c.nuv_report(mut s, v, 'usedIgnoredVar', s.nuv_used_ignored_data(v, .catch_clause))!
			}
			return false
		}
	} else if definition.kind == .parameter {
		if o.args == 'none' {
			return false
		}
		if is_identifier && nuv_test(o.args_pattern, name_text)! {
			if o.report_used_ignore_pattern && used {
				c.nuv_report(mut s, v, 'usedIgnoredVar', s.nuv_used_ignored_data(v, .parameter))!
			}
			return false
		}
		if o.args == 'after-used' && nuv_parent_is_function(name)
			&& !s.nuv_is_after_last_used_arg(v) {
			return false
		}
	} else if is_identifier && nuv_test(o.vars_pattern, name_text)! {
		if o.report_used_ignore_pattern && used && definition.kind != .ts_enum_member {
			c.nuv_report(mut s, v, 'usedIgnoredVar', s.nuv_used_ignored_data(v, .other))!
		}
		return false
	}
	if definition.kind == .variable && o.ignore_using_declarations {
		// def.parent.kind: the declaration of the declarator, or the for-in/of loop it heads.
		if declaration := node_parent(definition.node) {
			if using_kind(declaration) != '' {
				return false
			}
		}
	}
	if o.ignore_rest_siblings && (variable.defs.any(nuv_has_rest_sibling(it.name, false))
		|| variable.references.any(nuv_has_rest_sibling(tree.references[it].identifier, tree.references[it].write))) {
		return false
	}
	if s.eslint_used[v] {
		return false
	}
	return !used
}

// nuv_estree_parent is the parent of an identifier without parentheses.
fn nuv_estree_parent(n C.TSNode) ?C.TSNode {
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		parent = node_parent(parent)?
	}
	return parent
}

// nuv_parent_is_array_pattern: the ESTree parent of the name is an ArrayPattern. tree-sitter reads
// some assignment targets as an array expression (`[(a)] = b`); only a write there is in a pattern.
fn nuv_parent_is_array_pattern(name C.TSNode, write bool) bool {
	parent := nuv_estree_parent(name) or { return false }
	kind := node_kind(parent)
	return kind == 'array_pattern' || (write && kind == 'array')
}

// nuv_has_rest_sibling ports hasRestSibling on the parent of a name: a Property of an
// ObjectPattern whose last property is a RestElement (an object expression read as a pattern
// counts for a write).
fn nuv_has_rest_sibling(name C.TSNode, write bool) bool {
	parent := node_parent(name) or { return false }
	mut object := parent
	match node_kind(parent) {
		'object_pattern' {
			// A shorthand property.
			if node_kind(name) != 'shorthand_property_identifier_pattern' {
				return false
			}
		}
		'object' {
			if !write || node_kind(name) != 'shorthand_property_identifier' {
				return false
			}
		}
		'pair_pattern', 'pair' {
			if node_kind(parent) == 'pair' && !write {
				return false
			}
			value := node_field(parent, 'value') or { return false }
			if node_key(value) != node_key(name) {
				return false
			}
			object = node_parent(parent) or { return false }
		}
		else {
			return false
		}
	}
	if node_kind(object) !in ['object_pattern', 'object'] {
		return false
	}
	properties := named_children(object).filter(node_kind(it) != 'comment')
	if properties.len == 0 {
		return false
	}
	return node_kind(properties.last()) in ['rest_pattern', 'spread_element']
}

// nuv_parent_is_function ports isFunction(def.name.parent) for a parameter: the name is a
// parameter by itself (no default value, no destructuring, no parameter property) of a function
// with or without a body (not of a function type or a signature).
fn nuv_parent_is_function(name C.TSNode) bool {
	parent := node_parent(name) or { return false }
	if node_kind(parent) == 'arrow_function' {
		// `x => …`
		return true
	}
	if node_kind(parent) !in ['required_parameter', 'optional_parameter'] {
		return false
	}
	pattern := node_field(parent, 'pattern') or { return false }
	if node_key(pattern) != node_key(name) {
		return false
	}
	if _ := node_field(parent, 'value') {
		return false
	}
	if has_child_kind(parent, 'accessibility_modifier') || has_child_kind(parent, 'override_modifier')
		|| has_child_kind(parent, 'readonly') {
		return false
	}
	parameters := node_parent(parent) or { return false }
	function := node_parent(parameters) or { return false }
	match node_kind(function) {
		'function_declaration', 'generator_function_declaration', 'function_expression',
		'generator_function', 'arrow_function', 'method_definition', 'function_signature',
		'abstract_method_signature' {
			return true
		}
		'method_signature' {
			// TSEmptyBodyFunctionExpression in a class; TSMethodSignature elsewhere.
			owner := node_parent(function) or { return false }
			return node_kind(owner) == 'class_body'
		}
		else {
			return false
		}
	}
}

// nuv_is_after_last_used_arg ports isAfterLastUsedArg: no parameter of the same function after
// this one is used.
fn (s &NuvState) nuv_is_after_last_used_arg(v int) bool {
	tree := s.tree
	function := tree.variables[v].defs[0].node
	// The parameters are variables of the function's scope, in order.
	mut after := false
	for w in tree.scopes[tree.variables[v].scope].variables {
		if w == v {
			after = true
			continue
		}
		if !after {
			continue
		}
		variable := tree.variables[w]
		declares := variable.defs.any(it.kind == .parameter && node_key(it.node) == node_key(function)
			&& node_kind(it.node) == node_kind(function))
		if declares && (variable.references.len > 0 || s.eslint_used[w]) {
			return false
		}
	}
	return true
}

// nuv_report ports the rule's report: at the last write of the variable made from its variable
// scope, or else at its first identifier; with the fix or the suggestion of an import.
fn (mut c Checker) nuv_report(mut s NuvState, v int, message_id string, data map[string]string) ! {
	s.reported[v] = true
	tree := s.tree
	variable := tree.variables[v]
	variable_scope := tree.scopes[variable.scope].variable_scope
	mut id := if variable.identifiers.len > 0 {
		variable.identifiers[0]
	} else {
		variable.defs[0].name
	}
	for r in variable.references {
		reference := tree.references[r]
		if reference.write && tree.scopes[reference.from].variable_scope == variable_scope {
			id = reference.identifier
		}
	}
	mut finding := Finding{
		stmt:       position_of(id)
		message_id: message_id
		data:       data
	}
	if variable.defs.len == 1 && s.nuv_type(variable.defs[0]) == .import_binding {
		if import_fix := c.nuv_import_fix(mut s, v) {
			if s.o.autofix_imports {
				finding = Finding{
					...finding
					has_fix: true
					fix:     import_fix.fix
				}
			} else {
				finding = Finding{
					...finding
					suggestions: [
						Suggestion{
							message_id: import_fix.message_id
							data:       {
								'varName': variable.name
							}
							fix:        import_fix.fix
						},
					]
				}
			}
		}
	}
	s.findings << finding
}

// nuv_import_declaration is the ImportDeclaration (or `import x = require()`) a specifier is in.
fn nuv_import_declaration(n C.TSNode) ?C.TSNode {
	mut node := n
	for node_kind(node) != 'import_statement' {
		node = node_parent(node)?
	}
	return node
}

// nuv_declared_variables are getDeclaredVariables of an ImportDeclaration: the variables of its
// specifiers, in order (they are variables of the scope of `v`, one of them).
fn nuv_declared_variables(tree &ScopeTree, v int, declaration C.TSNode) []int {
	mut out := []int{}
	for w in tree.scopes[tree.variables[v].scope].variables {
		variable := tree.variables[w]
		for definition in variable.defs {
			if definition.kind != .import_binding {
				continue
			}
			parent := nuv_import_declaration(definition.node) or { continue }
			if node_key(parent) == node_key(declaration) {
				out << w
				break
			}
		}
	}
	return out
}

// nuv_specifier_count is the number of specifiers of an ImportDeclaration.
fn nuv_specifier_count(declaration C.TSNode) int {
	mut count := 0
	for part in named_children(declaration) {
		if node_kind(part) != 'import_clause' {
			continue
		}
		for clause in named_children(part) {
			match node_kind(clause) {
				'identifier', 'namespace_import' {
					count++
				}
				'named_imports' {
					count += named_children(clause).filter(node_kind(it) == 'import_specifier').len
				}
				else {}
			}
		}
	}
	return count
}

// NuvImportFix is what getImportFixer gives: the message of the suggestion and the fix.
struct NuvImportFix {
	message_id string
	fix        Fix
}

fn nuv_fix(message_id string, fix Fix) NuvImportFix {
	return NuvImportFix{
		message_id: message_id
		fix:        fix
	}
}

// nuv_import_fix ports getImportFixer.
fn (mut c Checker) nuv_import_fix(mut s NuvState, v int) ?NuvImportFix {
	tree := s.tree
	definition := tree.variables[v].defs[0]
	node := definition.node
	match node_kind(node) {
		'import_statement', 'import_alias' {
			// TSImportEqualsDeclaration: the whole declaration.
			return nuv_fix('removeUnusedImportDeclaration', c.nuv_remove_with_newline(node))
		}
		'namespace_import' {
			declaration := nuv_import_declaration(node)?
			return nuv_fix('removeUnusedImportDeclaration', c.nuv_remove_with_newline(declaration))
		}
		else {}
	}
	declaration := nuv_import_declaration(node)?
	all_unused := nuv_declared_variables(tree, v, declaration).all(s.reported[it])
	if nuv_specifier_count(declaration) == 1 || all_unused {
		return nuv_fix('removeUnusedImportDeclaration', c.nuv_remove_with_newline(declaration))
	}
	tokens := c.source_tokens(node)
	if node_kind(node) == 'identifier' {
		// ImportDefaultSpecifier: it and the comma after it.
		comma := tokens.after(node_end(node), false)?
		if !c.token_is(comma, ',') {
			return none
		}
		return nuv_fix('removeUnusedVar', nuv_remove_with(node, comma))
	}
	// ImportSpecifier
	mut used_named := 0
	for w in nuv_declared_variables(tree, v, declaration) {
		if s.reported[w] || node_kind(tree.variables[w].defs[0].node) != 'import_specifier' {
			continue
		}
		used_named++
	}
	if used_named == 0 {
		// `import Used, { Unused } from 'module'`: the comma and the braces go.
		left_curly := c.cti_token_between(declaration, node_start(declaration), node_end(declaration),
			'{')?
		left := tokens.before(left_curly.start, false)?
		right_curly := c.cti_token_between(declaration, node_start(declaration), node_end(declaration),
			'}')?
		if !c.token_is(left, ',') {
			return none
		}
		return nuv_fix('removeUnusedVar', fix_remove_range(left.start, right_curly.end))
	}
	// The comma before the specifier, or else the one after it.
	mut comma := tokens.before(node_start(node), false)?
	if !c.token_is(comma, ',') {
		comma = tokens.after(node_end(node), false)?
		if !c.token_is(comma, ',') {
			return none
		}
	}
	return nuv_fix('removeUnusedVar', nuv_remove_with(node, comma))
}

// nuv_remove_with removes a specifier and a comma next to it: from the start of the first to the
// end of the last.
fn nuv_remove_with(node C.TSNode, comma SourceToken) Fix {
	start := if comma.start < node_start(node) { comma.start } else { node_start(node) }
	end := if comma.end > node_end(node) { comma.end } else { node_end(node) }
	return fix_remove_range(start, end)
}

// nuv_remove_with_newline ports removeNodeWithTrailingNewline: the whole lines of the node, with
// the line break after them, when the node is all they hold; else the node.
fn (mut c Checker) nuv_remove_with_newline(node C.TSNode) Fix {
	start := node_start(node)
	end := c.tokens.last_end(node_end(node))
	line_start := offsets.line_start_before(c.src, start)
	line_end := nuv_next_line_start(c.src, end)
	if c.src[start..end] == js_trim(c.src[line_start..line_end]) {
		return fix_remove_range(line_start, line_end)
	}
	return fix_remove_range(start, end)
}

// nuv_next_line_start is where the line after the one of `offset` starts (ESLint's line breaks:
// `\r\n`, `\n`, `\r`, U+2028 and U+2029), or the end of the text on the last line.
fn nuv_next_line_start(src string, offset int) int {
	mut i := offset
	for i < src.len {
		b := src[i]
		if b == `\n` {
			return i + 1
		}
		if b == `\r` {
			return if i + 1 < src.len && src[i + 1] == `\n` { i + 2 } else { i + 1 }
		}
		if b == 0xE2 && i + 2 < src.len && src[i + 1] == 0x80 && (src[i + 2] == 0xA8 || src[i + 2] == 0xA9) {
			return i + 3
		}
		i++
	}
	return src.len
}

// nuv_global_comment_location ports getNameLocationInGlobalDirectiveComment for the first
// `/* global */` comment that names the variable: the offset of the name after `global`, preceded
// by a space or a comma and followed by the end, a space, a comma or a colon; or that of the
// comment's text when it is not there.
fn (mut c Checker) nuv_global_comment_location(root C.TSNode, name string) ?int {
	for node in c.nodes_of_kind(root, c'comment') {
		text := c.text(node)
		if !text.starts_with('/*') || text.len < 4 || !text.ends_with('*/') {
			continue
		}
		value := text[2..text.len - 2]
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
		base := node_start(node) + 2
		from := (value.index('global') or { return base }) + 6
		mut i := from
		for i < value.len {
			separator := utf8_char_len(value[i])
			character := value[i..i + separator].runes()[0]
			if character == `,` || is_js_space(character) {
				rest := value[i + separator..]
				if rest.starts_with(name) {
					after := rest[name.len..]
					if after == '' {
						return base + i + separator
					}
					next := after[..utf8_char_len(after[0])].runes()[0]
					if next == `,` || next == `:` || is_js_space(next) {
						return base + i + separator
					}
				}
			}
			i += separator
		}
		return base
	}
	return none
}

// nuv_ambient_marks ports the selectors of declarations that are ambiently exported and
// markDeclarationChildAsUsed: in a definition file, the declarations at the top level and those of
// namespaces; in any file, those of a declared namespace or module and of the namespaces inside
// one; unless the block has an export that overrides that (`export {}`, `export *`, `export =`,
// `export default name`).
fn (mut c Checker) nuv_ambient_marks(root C.TSNode, tree &ScopeTree, abs_path string) map[int]bool {
	mut marked := map[int]bool{}
	definition_file := is_definition_file(abs_path)
	for node in c.nodes_of_kinds(root, ['interface_declaration', 'type_alias_declaration',
		'class_declaration', 'abstract_class_declaration', 'function_signature', 'enum_declaration',
		'internal_module', 'module', 'ambient_declaration', 'lexical_declaration',
		'variable_declaration'], []string{}) {
		// `declare global {}` is a module; any other ambient_declaration only wraps its declaration.
		if node_kind(node) == 'ambient_declaration' && !has_child_kind(node, 'global') {
			continue
		}
		// The ESTree parent: tree-sitter wraps a declaration with `declare` in an ambient_declaration
		// and a statement-level `namespace` in an expression_statement.
		mut container := node_parent(node) or { continue }
		if node_kind(node) != 'ambient_declaration' && node_kind(container) == 'ambient_declaration' {
			container = node_parent(container) or { continue }
		}
		if node_kind(container) == 'expression_statement' {
			container = node_parent(container) or { continue }
		}
		mut applies := false
		block := container
		if node_kind(container) == 'program' {
			applies = definition_file
		} else if node_kind(container) == 'statement_block' {
			module := node_parent(container) or { continue }
			if !nuv_is_module(module) {
				continue
			}
			applies = definition_file || nuv_is_declared_module(module)
				|| nuv_in_declared_module_block(module)
		} else {
			continue
		}
		if !applies || nuv_has_overriding_export(block) {
			continue
		}
		c.nuv_mark_declaration(node, tree, mut marked)
	}
	return marked
}

// nuv_is_module: the node is a TSModuleDeclaration (`namespace`, `module`, `declare global`).
fn nuv_is_module(n C.TSNode) bool {
	kind := node_kind(n)
	return kind in ['internal_module', 'module']
		|| (kind == 'ambient_declaration' && has_child_kind(n, 'global'))
}

// nuv_is_declared_module: the TSModuleDeclaration has `declare`.
fn nuv_is_declared_module(module C.TSNode) bool {
	if node_kind(module) == 'ambient_declaration' {
		return has_child_kind(module, 'declare')
	}
	parent := node_parent(module) or { return false }
	return node_kind(parent) == 'ambient_declaration'
}

// nuv_in_declared_module_block: the module is inside the block of a declared module.
fn nuv_in_declared_module_block(module C.TSNode) bool {
	mut node := module
	for {
		node = node_parent(node) or { return false }
		if node_kind(node) != 'statement_block' {
			continue
		}
		owner := node_parent(node) or { return false }
		if nuv_is_module(owner) && nuv_is_declared_module(owner) {
			return true
		}
	}
	return false
}

// nuv_has_overriding_export ports hasOverridingExportStatement on the statements of a block or of
// the program.
fn nuv_has_overriding_export(block C.TSNode) bool {
	for statement in named_children(block) {
		if node_kind(statement) != 'export_statement' {
			continue
		}
		if _ := node_field(statement, 'declaration') {
			continue
		}
		if has_child_kind(statement, 'export_clause') || has_child_kind(statement, '*')
			|| has_child_kind(statement, 'namespace_export') {
			// `export { … }` (with or without a source), `export * from`.
			return true
		}
		if has_child_kind(statement, 'default') {
			if value := node_field(statement, 'value') {
				if node_kind(unwrap_parens(value)) == 'identifier' {
					return true
				}
			}
			continue
		}
		if has_child_kind(statement, '=') {
			// `export = x`
			return true
		}
	}
	return false
}

// nuv_mark_declaration ports markDeclarationChildAsUsed: the names the declaration declares are
// marked in its variable scope (the scope around it for a declared function or a namespace).
fn (mut c Checker) nuv_mark_declaration(node C.TSNode, tree &ScopeTree, mut marked map[int]bool) {
	mut declared := []C.TSNode{}
	match node_kind(node) {
		'lexical_declaration', 'variable_declaration' {
			// The PatternVisitor on each declarator: its names and the identifiers of its
			// initializer that a pattern would bind.
			builder := ScopeBuilder{
				src:    c.src
				tokens: c.tokens
			}
			for declarator in named_children(node) {
				if node_kind(declarator) != 'variable_declarator' {
					continue
				}
				mut targets := []ScopeTarget{}
				mut rhs := []C.TSNode{}
				builder.collect_pattern(declarator, []C.TSNode{}, -1, mut targets, mut rhs)
				for target in targets {
					declared << target.ident
				}
			}
		}
		'ambient_declaration' {
			// `declare global {}`: its name is the Identifier `global`.
		}
		else {
			if name := node_field(node, 'name') {
				if node_kind(name) in ['identifier', 'type_identifier'] {
					declared << name
				}
			}
		}
	}
	mut scope := tree.get_scope(node)
	upper_scope := node_kind(node) in ['function_signature', 'internal_module', 'module',
		'ambient_declaration']
	if tree.scopes[scope].variable_scope != scope {
		scope = tree.scopes[scope].variable_scope
	} else if upper_scope && tree.scopes[scope].upper >= 0 {
		scope = tree.scopes[scope].upper
	}
	if node_kind(node) == 'ambient_declaration' {
		if v := tree.scopes[scope].set['global'] {
			marked[v] = true
		}
		return
	}
	for name in declared {
		if v := tree.scopes[scope].set[c.nuv_name(name)] {
			marked[v] = true
		}
	}
}

// nuv_name is the name of an identifier (escapes applied).
fn (c &Checker) nuv_name(n C.TSNode) string {
	text := c.text(n)
	if !text.contains('\\') {
		return text
	}
	return cooked_string(text, false) or { text }
}
