module rules

import json2
import time
import treesitter { has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-empty-function` rule of typescript-eslint 8.62.0, which extends the rule of
// ESLint 10.6.0 with the same name, with its option `allow` and its suggestion. The wrapper adds
// `private-constructors` and `protected-constructors`; the core rule already allows constructors
// with parameter properties, and decorated or overriding methods with `decoratedFunctions` and
// `overrideMethods`.

const nef_messages = {
	'unexpected':     'Unexpected empty {{name}}.'
	'suggestComment': 'Add comment inside empty {{name}}.'
}

struct NefOptions {
	allow []string
}

fn nef_options(options []json2.Any) !NefOptions {
	o := option_object(no_empty_function, options, ['allow'])!
	return NefOptions{
		allow: o.string_list('allow')!
	}
}

fn (mut c Checker) lint_no_empty_function(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nef_options(c.rule_options(no_empty_function))!
	mut findings := []Finding{}
	mut checked := 0
	// ArrowFunctionExpression, FunctionDeclaration and FunctionExpression (the value of a method).
	for node in c.nodes_of_kinds(root, ['function_declaration', 'generator_function_declaration',
		'function_expression', 'generator_function', 'arrow_function', 'method_definition'], []) {
		body := node_field(node, 'body') or { continue }
		// A block without statements nor comments (tree-sitter may put a comment after its `}`
		// inside it).
		if node_kind(body) != 'statement_block' || named_children(body).len > 0 {
			continue
		}
		body_end := c.cm_node_end(body)
		if c.source_tokens(node).comments_inside(node_start(body), body_end).len > 0 {
			continue
		}
		// typescript-estree leaves out the initializer of an abstract field.
		if parent := estree_parent(node) {
			if node_kind(parent) == 'public_field_definition' && has_child_kind(parent, 'abstract') {
				continue
			}
		}
		checked++
		if c.nef_is_allowed(node, o) {
			continue
		}
		name := c.core_function_name(node)
		_, suggestion := c.suggestion('suggestComment', {
			'name': name
		}, [fix_replace_range(node_start(body) + 1, body_end - 1, ' /* empty */ ')])!
		findings << Finding{
			stmt:        position_of(body)
			message_id:  'unexpected'
			data:        {
				'name': name
			}
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nef_is_allowed ports isAllowedEmptyFunction and the checks the wrapper makes before it.
fn (c &Checker) nef_is_allowed(node C.TSNode, o NefOptions) bool {
	kind := c.nef_kind(node)
	if kind in o.allow {
		return true
	}
	is_class_method := node_kind(node) == 'method_definition'
		&& node_kind(node_parent(node) or { node }) == 'class_body'
	if kind == 'constructors' {
		if cm_parameters(node).any(cm_is_parameter_property(it)) {
			return true
		}
		accessibility := c.cm_accessibility(node)
		return (accessibility == 'private' && 'private-constructors' in o.allow)
			|| (accessibility == 'protected' && 'protected-constructors' in o.allow)
	}
	// /(?:g|s)etters|methods$/iu: the methods, getters and setters of a class have decorators and
	// `override` (constructors get none from typescript-estree).
	if is_class_method && (kind in ['getters', 'setters'] || kind.to_lower().ends_with('methods')) {
		if 'decoratedFunctions' in o.allow && cm_decorators(node).len > 0 {
			return true
		}
		if 'overrideMethods' in o.allow && has_child_kind(node, 'override_modifier') {
			return true
		}
	}
	return false
}

// nef_kind ports getKind: arrowFunctions, getters, setters, constructors, or functions or methods
// with the prefix generator or async (`generatorMethods`).
fn (c &Checker) nef_kind(node C.TSNode) string {
	if node_kind(node) == 'arrow_function' {
		return 'arrowFunctions'
	}
	mut kind := 'functions'
	if node_kind(node) == 'method_definition' {
		// A MethodDefinition in a class, a Property of an object.
		if has_child_kind(node, 'get') {
			return 'getters'
		}
		if has_child_kind(node, 'set') {
			return 'setters'
		}
		holder := node_parent(node) or { node }
		if node_kind(holder) == 'class_body' && c.cm_method_kind(node) == 'constructor' {
			return 'constructors'
		}
		kind = 'methods'
	}
	prefix := if is_generator(node) {
		'generator'
	} else if has_child_kind(node, 'async') {
		'async'
	} else {
		return kind
	}
	return prefix + kind[0..1].to_upper() + kind[1..]
}
