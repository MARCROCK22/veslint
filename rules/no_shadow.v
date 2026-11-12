module rules

import json2
import offsets
import time
import treesitter { has_child_kind, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-shadow` rule of typescript-eslint 8.62.0, with its options `allow`,
// `builtinGlobals`, `hoist`, `ignoreFunctionTypeParameterNameValueShadow`,
// `ignoreOnInitialization` and `ignoreTypeValueShadow`.

const nsh_messages = {
	'noShadow':       "'{{name}}' is already declared in the upper scope on line {{shadowedLine}} column {{shadowedColumn}}."
	'noShadowGlobal': "'{{name}}' is already a global variable."
}

struct NshOptions {
	allow                                            []string
	builtin_globals                                  bool
	hoist                                            string
	ignore_function_type_parameter_name_value_shadow bool
	ignore_on_initialization                         bool
	ignore_type_value_shadow                         bool
}

fn nsh_options(options []json2.Any) !NshOptions {
	o := option_object(no_shadow, options, ['allow', 'builtinGlobals', 'hoist',
		'ignoreFunctionTypeParameterNameValueShadow', 'ignoreOnInitialization', 'ignoreTypeValueShadow'])!
	return NshOptions{
		allow:                                            o.string_list('allow')!
		builtin_globals:                                  o.bool_value('builtinGlobals')!
		hoist:                                            o.string_value('hoist', [
			'all',
			'functions',
			'functions-and-types',
			'never',
			'types',
		])!
		ignore_function_type_parameter_name_value_shadow: o.bool_value('ignoreFunctionTypeParameterNameValueShadow')!
		ignore_on_initialization:                         o.bool_value('ignoreOnInitialization')!
		ignore_type_value_shadow:                         o.bool_value('ignoreTypeValueShadow')!
	}
}

fn (mut c Checker) lint_no_shadow(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nsh_options(c.rule_options(no_shadow))!
	tree := c.scope_tree(root)
	definition_file := is_definition_file(abs_path)
	mut lines := offsets.LineStarts{}
	mut has_lines := false
	mut findings := []Finding{}
	mut checked := 0
	// Program:exit: the scopes below the global one, each popped from a stack that then takes its
	// child scopes.
	mut stack := tree.scopes[tree.global_scope()].children.clone()
	for stack.len > 0 {
		scope := stack.pop()
		stack << tree.scopes[scope].children
		if nsh_is_global_augmentation(tree, scope) {
			continue
		}
		for v in tree.scopes[scope].variables {
			checked++
			shadowed := c.nsh_shadowed(tree, scope, v, o, definition_file)
			if shadowed < 0 {
				continue
			}
			variable := tree.variables[v]
			shadowed_variable := tree.variables[shadowed]
			if shadowed_variable.identifiers.len == 0 {
				findings << Finding{
					stmt:       position_of(variable.identifiers[0])
					message_id: 'noShadowGlobal'
					data:       {
						'name': variable.name
					}
				}
				continue
			}
			if !has_lines {
				lines = offsets.line_starts(c.src)
				has_lines = true
			}
			line, column := c.line_column(lines, node_start(shadowed_variable.identifiers[0]))
			findings << Finding{
				stmt:       position_of(variable.identifiers[0])
				message_id: 'noShadow'
				data:       {
					'name':           variable.name
					'shadowedLine':   line.str()
					'shadowedColumn': column.str()
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nsh_shadowed ports the checks of checkForShadows for one variable of a scope: the variable it
// shadows when that is reported, or -1.
fn (c &Checker) nsh_shadowed(tree &ScopeTree, scope int, v int, o NshOptions, definition_file bool) int {
	variable := tree.variables[v]
	// `arguments` and other variables without identifiers, `this` parameters, the name of a class
	// or of an enum in its own scope, allowed names and declared things in a definition file.
	if variable.identifiers.len == 0 {
		return -1
	}
	if variable.defs.len > 0 && variable.defs[0].kind == .parameter && variable.name == 'this' {
		return -1
	}
	block := tree.scopes[scope].block
	if node_kind(block) in ['class_declaration', 'abstract_class_declaration', 'enum_declaration'] {
		if name := node_field(block, 'name') {
			if node_key(name) == node_key(variable.identifiers[0]) {
				return -1
			}
		}
	}
	if variable.name in o.allow {
		return -1
	}
	if definition_file && variable.defs.any(nsh_is_declared(it)) {
		return -1
	}
	upper := tree.scopes[scope].upper
	if upper < 0 {
		return -1
	}
	shadowed := tree.find_variable(upper, variable.name, -1)
	if shadowed < 0 {
		return -1
	}
	shadowed_variable := tree.variables[shadowed]
	if nsh_is_type_value_shadow(variable, shadowed_variable, o)
		|| nsh_is_function_type_parameter_shadow(variable, shadowed_variable, o)
		|| (nsh_is_generic_of_static_method(variable) && nsh_is_generic_of_class(shadowed_variable))
		|| c.nsh_is_external_declaration_merging(tree, scope, variable, shadowed_variable) {
		return -1
	}
	if shadowed_variable.identifiers.len == 0
		&& !(o.builtin_globals && nsh_is_eslint_global(shadowed_variable)) {
		return -1
	}
	if nsh_is_on_initializer(variable, shadowed_variable) {
		return -1
	}
	if o.ignore_on_initialization && nsh_is_init_pattern(tree, variable, shadowed_variable) {
		return -1
	}
	if o.hoist != 'all' && c.nsh_is_in_tdz(variable, shadowed_variable, o) {
		return -1
	}
	return shadowed
}

// nsh_is_global_augmentation ports isGlobalAugmentation: the scope is, or is inside, a
// `declare global {}` (or a `global {}` in a declared module).
fn nsh_is_global_augmentation(tree &ScopeTree, scope int) bool {
	mut s := scope
	for s >= 0 {
		block := tree.scopes[s].block
		if tree.scopes[s].kind == .ts_module && node_kind(block) == 'ambient_declaration'
			&& has_child_kind(block, 'global') {
			return true
		}
		s = tree.scopes[s].upper
	}
	return false
}

// nsh_is_declared: the definition is a declaration with the `declare` modifier (a variable, a
// class, an enum or a namespace), for isDeclareInDTSFile.
fn nsh_is_declared(definition ScopeDefinition) bool {
	mut node := definition.node
	match definition.kind {
		.variable {
			// def.parent.declare: the VariableDeclaration of the declarator.
			if node_kind(node) != 'variable_declarator' {
				return false
			}
			node = node_parent(node) or { return false }
		}
		.class_name, .ts_enum_name, .ts_module_name {}
		else {
			return false
		}
	}
	parent := node_parent(node) or { return false }
	return node_kind(parent) == 'ambient_declaration'
}

// nsh_is_eslint_global ports `'writeable' in shadowed`: the implicit variables of the libs and the
// globals ESLint declares have that key.
fn nsh_is_eslint_global(variable ScopeVariable) bool {
	return variable.lib || variable.eslint_implicit_global_setting != ''
		|| variable.eslint_explicit_global
}

// nsh_is_type_value_shadow ports isTypeValueShadow: a value shadows a type or a type a value. A
// variable without definitions (a global, an implicit variable of a lib) counts as a value.
fn nsh_is_type_value_shadow(variable ScopeVariable, shadowed ScopeVariable, o NshOptions) bool {
	if !o.ignore_type_value_shadow {
		return false
	}
	shadowed_value := shadowed.defs.len == 0
		|| (!unused_is_type_import(shadowed.defs[0]) && shadowed.is_value_variable())
	return variable.is_value_variable() != shadowed_value
}

// nsh_is_function_type_parameter_shadow ports isFunctionTypeParameterNameValueShadow: a parameter
// of a signature without a body (a function type, a call or construct signature, a method
// signature, a `declare function`, an overload) named like a value.
fn nsh_is_function_type_parameter_shadow(variable ScopeVariable, shadowed ScopeVariable, o NshOptions) bool {
	if !o.ignore_function_type_parameter_name_value_shadow || !shadowed.is_value_variable() {
		return false
	}
	return variable.defs.all(node_kind(it.node) in ['call_signature', 'function_type',
		'method_signature', 'abstract_method_signature', 'function_signature', 'construct_signature',
		'constructor_type'])
}

// nsh_type_parameter_owner is the node a type variable is a type parameter of: the parent of its
// TSTypeParameterDeclaration.
fn nsh_type_parameter_owner(variable ScopeVariable) ?C.TSNode {
	if !variable.is_type_variable() || variable.identifiers.len == 0 {
		return none
	}
	parameter := node_parent(variable.identifiers[0])?
	if node_kind(parameter) != 'type_parameter' {
		return none
	}
	declaration := node_parent(parameter)?
	if node_kind(declaration) != 'type_parameters' {
		return none
	}
	return node_parent(declaration)
}

// nsh_is_generic_of_static_method ports isGenericOfStaticMethod: a type parameter of a static
// method of a class (with or without a body).
fn nsh_is_generic_of_static_method(variable ScopeVariable) bool {
	method := nsh_type_parameter_owner(variable) or { return false }
	if node_kind(method) == 'method_signature' {
		parent := node_parent(method) or { return false }
		if node_kind(parent) != 'class_body' {
			return false
		}
	} else if node_kind(method) != 'method_definition' {
		return false
	}
	return has_child_kind(method, 'static')
}

// nsh_is_generic_of_class ports isGenericOfClass: a type parameter of a class.
fn nsh_is_generic_of_class(variable ScopeVariable) bool {
	class := nsh_type_parameter_owner(variable) or { return false }
	return node_kind(class) in ['class_declaration', 'abstract_class_declaration', 'class']
}

// nsh_is_external_declaration_merging ports isExternalDeclarationMerging: an interface or a type
// alias in `declare module 'm' {}` with the name of a type import from 'm'.
fn (c &Checker) nsh_is_external_declaration_merging(tree &ScopeTree, scope int, variable ScopeVariable, shadowed ScopeVariable) bool {
	if shadowed.defs.len == 0 || variable.defs.len == 0 {
		return false
	}
	first := shadowed.defs[0]
	if !unused_is_type_import(first) {
		return false
	}
	// firstDefinition.parent is an ImportDeclaration (not an `import x = require()`).
	mut declaration := first.node
	for node_kind(declaration) != 'import_statement' {
		declaration = node_parent(declaration) or { return false }
	}
	if has_child_kind(declaration, 'import_require_clause') {
		return false
	}
	source := node_field(declaration, 'source') or { return false }
	block := tree.scopes[scope].block
	if tree.scopes[scope].kind != .ts_module || node_kind(block) != 'module' {
		return false
	}
	name := node_field(block, 'name') or { return false }
	if node_kind(name) != 'string' || c.nsh_string_value(name) != c.nsh_string_value(source) {
		return false
	}
	return node_kind(variable.defs[0].node) in ['interface_declaration', 'type_alias_declaration']
}

// nsh_string_value is the value of a string literal.
fn (c &Checker) nsh_string_value(n C.TSNode) string {
	text := c.text(n)
	if text.len < 2 {
		return text
	}
	return cooked_string(text[1..text.len - 1], false) or { text }
}

// nsh_initializer ports how isOnInitializer finds the initializer of a name: the init of its
// VariableDeclarator or the right side of its AssignmentPattern.
fn nsh_initializer(name C.TSNode) ?C.TSNode {
	parent := node_parent(name)?
	match node_kind(parent) {
		'variable_declarator' {
			id := node_field(parent, 'name')?
			if node_key(id) == node_key(name) {
				return unwrap_parens(node_field(parent, 'value')?)
			}
		}
		'assignment_pattern', 'object_assignment_pattern' {
			left := node_field(parent, 'left')?
			if node_key(left) == node_key(name) {
				return unwrap_parens(node_field(parent, 'right')?)
			}
		}
		'required_parameter', 'optional_parameter' {
			// A parameter with a default value is an AssignmentPattern.
			return unwrap_parens(node_field(parent, 'value')?)
		}
		else {}
	}
	return none
}

// nsh_unwrap_expression ports unwrapExpression: from the node up through the logical expressions
// and the branches (not the test) of conditional expressions it is part of.
fn nsh_unwrap_expression(n C.TSNode) C.TSNode {
	mut node := n
	for {
		mut parent := node_parent(node) or { return node }
		for node_kind(parent) == 'parenthesized_expression' {
			parent = node_parent(parent) or { return node }
		}
		if estree_binary_kind(parent) == 'LogicalExpression' {
			node = parent
			continue
		}
		if node_kind(parent) == 'ternary_expression' {
			condition := node_field(parent, 'condition') or { return node }
			if node_key(unwrap_parens(condition)) != node_key(node) {
				node = parent
				continue
			}
		}
		return node
	}
	return node
}

// nsh_is_on_initializer ports isOnInitializer: a function or class expression named like the
// variable it initializes, directly or through `||` and `?:` (`var a = function a() {}`).
fn nsh_is_on_initializer(variable ScopeVariable, shadowed ScopeVariable) bool {
	if shadowed.defs.len == 0 || variable.defs.len == 0 {
		return false
	}
	inner := variable.defs[0]
	kind := node_kind(inner.node)
	if !((inner.kind == .function_name && kind in ['function_expression', 'generator_function'])
		|| (inner.kind == .class_name && kind == 'class')) {
		return false
	}
	initializer := nsh_initializer(shadowed.defs[0].name) or { return false }
	node := inner.node
	if !(node_start(initializer) <= node_start(node) && node_end(node) <= node_end(initializer)) {
		return false
	}
	return node_key(initializer) == node_key(nsh_unwrap_expression(node))
}

// nsh_is_estree_call: an ESTree CallExpression (not a tagged template nor an `import()`).
fn nsh_is_estree_call(n C.TSNode) bool {
	if node_kind(n) != 'call_expression' {
		return false
	}
	arguments := node_field(n, 'arguments') or { return false }
	function := node_field(n, 'function') or { return false }
	return node_kind(arguments) == 'arguments' && node_kind(function) != 'import'
}

// nsh_is_init_pattern ports isInitPatternNode: the variable is in a function or arrow expression
// (a method is a function expression too) defined in the scope of the shadowed variable, inside a
// call that is in the shadowed variable's initializer.
fn nsh_is_init_pattern(tree &ScopeTree, variable ScopeVariable, shadowed ScopeVariable) bool {
	if shadowed.defs.len == 0 {
		return false
	}
	variable_scope := tree.scopes[variable.scope].variable_scope
	function := tree.scopes[variable_scope].block
	if node_kind(function) !in ['arrow_function', 'function_expression', 'generator_function',
		'method_definition'] {
		return false
	}
	// getOuterScope
	mut outer := tree.scopes[variable_scope].upper
	if outer >= 0 && tree.scopes[outer].kind == .function_expression_name {
		outer = tree.scopes[outer].upper
	}
	if outer != shadowed.scope {
		return false
	}
	// findSelfOrAncestor(fun.parent, CallExpression): a method's function is the child of the
	// method itself.
	mut node := function
	if node_kind(function) != 'method_definition' {
		node = node_parent(function) or { return false }
	}
	for !nsh_is_estree_call(node) {
		node = node_parent(node) or { return false }
	}
	return in_initializer(shadowed.defs[0].name, node_end(node))
}

// nsh_is_in_tdz ports isInTdz: the variable is declared before the shadowed one, which `hoist`
// does not hoist.
fn (c &Checker) nsh_is_in_tdz(variable ScopeVariable, shadowed ScopeVariable, o NshOptions) bool {
	if variable.defs.len == 0 || shadowed.defs.len == 0 {
		return false
	}
	if c.identifier_end(variable.defs[0].name) >= node_start(shadowed.defs[0].name) {
		return false
	}
	outer := node_kind(shadowed.defs[0].node)
	is_function := outer in ['function_declaration', 'generator_function_declaration']
	is_type := outer in ['interface_declaration', 'type_alias_declaration']
	return match o.hoist {
		'functions' { !is_function }
		'types' { !is_type }
		'functions-and-types' { !is_function && !is_type }
		else { true }
	}
}
