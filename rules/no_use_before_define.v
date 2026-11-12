module rules

import json2
import time
import treesitter { node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-use-before-define` rule of typescript-eslint 8.62.0, with its options: the
// string 'nofunc', or an object with `allowNamedExports`, `classes`, `enums`, `functions`,
// `ignoreTypeReferences`, `typedefs` and `variables`.

const nubd_messages = {
	'noUseBeforeDefine': "'{{name}}' was used before it was defined."
}

struct NubdOptions {
	allow_named_exports    bool
	classes                bool
	enums                  bool
	functions              bool
	ignore_type_references bool
	typedefs               bool
	variables              bool
}

// nubd_options ports parseOptions on the effective option: 'nofunc' turns `functions` off; of an
// object, every key but a `false` leaves its check on.
fn nubd_options(options []json2.Any) !NubdOptions {
	if options.len == 0 {
		return NubdOptions{
			classes:                true
			enums:                  true
			functions:              true
			ignore_type_references: true
			typedefs:               true
			variables:              true
		}
	}
	first := options[0]
	if first is string {
		if first != 'nofunc' {
			return error("the option of `${no_use_before_define}` must be 'nofunc' or an object")
		}
		return NubdOptions{
			classes:                true
			enums:                  true
			ignore_type_references: true
			typedefs:               true
			variables:              true
		}
	}
	o := option_object(no_use_before_define, options, ['allowNamedExports', 'classes', 'enums',
		'functions', 'ignoreTypeReferences', 'typedefs', 'variables'])!
	return NubdOptions{
		allow_named_exports:    nubd_flag(o, 'allowNamedExports')!
		classes:                nubd_flag(o, 'classes')!
		enums:                  nubd_flag(o, 'enums')!
		functions:              nubd_flag(o, 'functions')!
		ignore_type_references: nubd_flag(o, 'ignoreTypeReferences')!
		typedefs:               nubd_flag(o, 'typedefs')!
		variables:              nubd_flag(o, 'variables')!
	}
}

// nubd_flag is `options[key] !== false`.
fn nubd_flag(o OptionObject, key string) !bool {
	value := o.values[key] or { return true }
	if value !is bool {
		return error('option `${key}` of `${no_use_before_define}` must be true or false')
	}
	return value as bool
}

fn (mut c Checker) lint_no_use_before_define(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nubd_options(c.rule_options(no_use_before_define))!
	tree := c.scope_tree(root)
	mut findings := []Finding{}
	mut checked := 0
	// findVariablesInScope from the global scope: the references of each scope, then its child
	// scopes, in order.
	mut stack := [tree.global_scope()]
	for stack.len > 0 {
		scope := stack.pop()
		for i := tree.scopes[scope].children.len - 1; i >= 0; i-- {
			stack << tree.scopes[scope].children[i]
		}
		for r in tree.scopes[scope].references {
			checked++
			reference := tree.references[r]
			if c.nubd_reported(tree, reference, o) {
				findings << Finding{
					stmt:       position_of(reference.identifier)
					message_id: 'noUseBeforeDefine'
					data:       {
						'name': reference.name
					}
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nubd_reported: the reference is reported. Initializations, references to no variable or to one
// without identifiers (a global, an implicit variable of a lib), references after the definition
// (except in its initializer) and those the options allow are not.
fn (c &Checker) nubd_reported(tree &ScopeTree, reference ScopeReference, o NubdOptions) bool {
	if reference.init {
		return false
	}
	if !o.allow_named_exports && nubd_is_named_export(reference) {
		return reference.resolved < 0
			|| !c.nubd_defined_before_use(tree, reference.resolved, reference)
	}
	if reference.resolved < 0 {
		return false
	}
	variable := tree.variables[reference.resolved]
	if variable.identifiers.len == 0 || c.nubd_defined_before_use(tree, reference.resolved, reference)
		|| !nubd_is_forbidden(tree, variable, reference, o)
		|| nubd_in_class_decorator(variable, reference)
		|| tree.scopes[reference.from].kind == .function_type {
		return false
	}
	return true
}

// nubd_is_named_export ports isNamedExports: the identifier is the local name of an export
// specifier.
fn nubd_is_named_export(reference ScopeReference) bool {
	parent := node_parent(reference.identifier) or { return false }
	if node_kind(parent) != 'export_specifier' {
		return false
	}
	local := node_field(parent, 'name') or { return false }
	return node_key(local) == node_key(reference.identifier)
}

// nubd_defined_before_use ports isDefinedBeforeUse: the first identifier of the variable ends
// before the reference does, and a value reference is not in the variable's initializer. Both ends
// are ESTree's: the reference the JSX pragma makes has the declared identifier itself, whose range
// takes its type annotation (`declare const React: any`).
fn (c &Checker) nubd_defined_before_use(tree &ScopeTree, v int, reference ScopeReference) bool {
	variable := tree.variables[v]
	if variable.identifiers.len == 0 {
		// identifiers[0].range: typescript-eslint throws; nothing that reaches here lacks them
		// but a named export of an implicit variable, which is not defined in the file.
		return false
	}
	return c.identifier_end(variable.identifiers[0]) <= c.identifier_end(reference.identifier)
		&& !(reference.value_ref && c.nubd_in_initializer(tree, v, reference))
}

// nubd_in_initializer ports isInInitializer: the reference is made in the scope of the variable,
// inside the initializer of its first identifier's declaration.
fn (c &Checker) nubd_in_initializer(tree &ScopeTree, v int, reference ScopeReference) bool {
	variable := tree.variables[v]
	if variable.scope != reference.from {
		return false
	}
	return in_initializer(variable.identifiers[0], c.identifier_end(reference.identifier))
}

// nubd_is_forbidden ports isForbidden: whether the options report this use before the definition.
fn nubd_is_forbidden(tree &ScopeTree, variable ScopeVariable, reference ScopeReference, o NubdOptions) bool {
	if o.ignore_type_references && (reference.type_ref || inside_type_query(reference.identifier)) {
		return false
	}
	if variable.defs.len == 0 {
		return true
	}
	kind := variable.defs[0].kind
	if kind == .function_name {
		return o.functions
	}
	outer := tree.scopes[variable.scope].variable_scope != tree.scopes[reference.from].variable_scope
	if kind == .class_name && outer {
		return o.classes
	}
	if kind == .variable && outer {
		return o.variables
	}
	if kind == .ts_enum_name && outer {
		return o.enums
	}
	if kind == .type_definition {
		return o.typedefs
	}
	return true
}

// nubd_in_class_decorator ports isClassRefInClassDecorator: the variable is a class and the
// reference is inside one of its decorators (tree-sitter puts those of `@dec export class C {}`
// on the export).
fn nubd_in_class_decorator(variable ScopeVariable, reference ScopeReference) bool {
	if variable.defs.len == 0 || variable.defs[0].kind != .class_name {
		return false
	}
	class := variable.defs[0].node
	mut decorators := children_of_kind(class, 'decorator')
	if parent := node_parent(class) {
		if node_kind(parent) == 'export_statement' {
			decorators << children_of_kind(parent, 'decorator')
		}
	}
	identifier := reference.identifier
	for decorator in decorators {
		if node_start(identifier) >= node_start(decorator) && node_end(identifier) <= node_end(decorator) {
			return true
		}
	}
	return false
}
