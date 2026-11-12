module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-unused-expressions` rule of typescript-eslint 8.62.0, which extends the rule of
// ESLint 10.6.0 with the same name, with its options `allowShortCircuit`, `allowTaggedTemplates`,
// `allowTernary`, `enforceForJSX` and `ignoreDirectives`. What the wrapper adds (optional calls
// and `import()` are valid, a TypeScript expression is checked by its expression, directives are
// skipped) the core rule of ESLint 10 already does.

const nuex_messages = {
	'unusedExpression': 'Expected an assignment or function call and instead saw an expression.'
}

struct NuexOptions {
	allow_short_circuit    bool
	allow_tagged_templates bool
	allow_ternary          bool
	enforce_for_jsx        bool
	ignore_directives      bool
}

fn nuex_options(options []json2.Any) !NuexOptions {
	o := option_object(no_unused_expressions, options, ['allowShortCircuit', 'allowTaggedTemplates',
		'allowTernary', 'enforceForJSX', 'ignoreDirectives'])!
	return NuexOptions{
		allow_short_circuit:    o.bool_value('allowShortCircuit')!
		allow_tagged_templates: o.bool_value('allowTaggedTemplates')!
		allow_ternary:          o.bool_value('allowTernary')!
		enforce_for_jsx:        o.bool_value('enforceForJSX')!
		ignore_directives:      o.bool_value('ignoreDirectives')!
	}
}

fn (mut c Checker) lint_no_unused_expressions(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nuex_options(c.rule_options(no_unused_expressions))!
	mut findings := []Finding{}
	mut checked := 0
	for statement in c.nodes_of_kind(root, c'expression_statement') {
		expression := first_named(statement) or { continue }
		// tree-sitter wraps `namespace X {}` in an expression_statement; ESTree has a
		// TSModuleDeclaration.
		if node_kind(expression) == 'internal_module' {
			continue
		}
		// Only the body of a `for` is a statement; its head holds expressions.
		if parent := node_parent(statement) {
			if node_kind(parent) == 'for_statement' {
				body := node_field(parent, 'body') or { continue }
				if node_key(body) != node_key(statement) {
					continue
				}
			}
		}
		checked++
		// A directive of typescript-estree (`directive` is set), or, with ignoreDirectives, a
		// statement that looks like one at the start of a function or a module (isDirective).
		if nuex_in_prologue(statement, true) {
			continue
		}
		if !c.nuex_is_disallowed(expression, o, 0) {
			continue
		}
		if o.ignore_directives && nuex_in_prologue(statement, false) {
			continue
		}
		findings << Finding{
			stmt:       position_of(statement)
			message_id: 'unusedExpression'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nuex_is_disallowed ports Checker.isDisallowed: the expression has no side effect, by its ESTree
// type. A ChainExpression is its expression; unknown types (calls, assignments, `await`, `new`,
// TSSatisfiesExpression…) are allowed.
fn (c &Checker) nuex_is_disallowed(n C.TSNode, o NuexOptions, depth int) bool {
	node := unwrap_parens(n)
	if depth >= max_expression_depth {
		return false
	}
	match node_kind(node) {
		'array', 'arrow_function', 'class', 'function_expression', 'generator_function',
		'identifier', 'undefined', 'string', 'number', 'true', 'false', 'null', 'regex',
		'member_expression', 'subscript_expression', 'meta_property', 'object',
		'sequence_expression', 'template_string', 'this' {
			return true
		}
		'binary_expression' {
			if estree_binary_kind(node) == 'LogicalExpression' && o.allow_short_circuit {
				return c.nuex_is_disallowed(node_field(node, 'right') or { return false }, o,
					depth + 1)
			}
			return true
		}
		'ternary_expression' {
			if o.allow_ternary {
				consequence := node_field(node, 'consequence') or { return false }
				alternative := node_field(node, 'alternative') or { return false }
				return c.nuex_is_disallowed(consequence, o, depth + 1)
					|| c.nuex_is_disallowed(alternative, o, depth + 1)
			}
			return true
		}
		'call_expression' {
			// A TaggedTemplateExpression; any other call (`import()` too) is allowed.
			arguments := node_field(node, 'arguments') or { return false }
			return node_kind(arguments) == 'template_string' && !o.allow_tagged_templates
		}
		'jsx_element', 'jsx_self_closing_element' {
			return o.enforce_for_jsx
		}
		'unary_expression' {
			return operator_of(node) !in ['void', 'delete']
		}
		'as_expression', 'type_assertion', 'non_null_expression', 'instantiation_expression' {
			// TSAsExpression, TSTypeAssertion, TSNonNullExpression and TSInstantiationExpression:
			// their expression.
			inner := if node_kind(node) == 'type_assertion' {
				named_children(node).filter(node_kind(it) != 'type_arguments')[0] or { return false }
			} else {
				first_named(node) or { return false }
			}
			return c.nuex_is_disallowed(inner, o, depth + 1)
		}
		else {
			return false
		}
	}
}

// nuex_in_prologue tells whether a statement is in the directive prologue of its body: it and the
// statements before it are expression statements of a string. With `parser` it is typescript-
// estree's `directive` (a string that is not parenthesized, in the program, a module, a function
// or a static block); otherwise ESLint's isDirective for ignoreDirectives (looksLikeDirective lets
// parentheses in, and isTopLevelExpressionStatement leaves static blocks out).
fn nuex_in_prologue(statement C.TSNode, parser bool) bool {
	parent := node_parent(statement) or { return false }
	if !nuex_can_contain_directive(parent, parser) {
		return false
	}
	for sibling in named_children(parent) {
		if node_kind(sibling) == 'hash_bang_line' {
			continue
		}
		if node_kind(sibling) != 'expression_statement' {
			return false
		}
		expression := first_named(sibling) or { return false }
		literal := if parser { expression } else { unwrap_parens(expression) }
		if node_kind(literal) != 'string' {
			return false
		}
		if node_key(sibling) == node_key(statement) {
			return true
		}
	}
	return false
}

// nuex_can_contain_directive: the body has a directive prologue: the program, the block of a
// module or namespace, of a function or method, and, for typescript-estree, of a static block.
fn nuex_can_contain_directive(body C.TSNode, parser bool) bool {
	if node_kind(body) == 'program' {
		return true
	}
	if node_kind(body) != 'statement_block' {
		return false
	}
	holder := node_parent(body) or { return false }
	return match node_kind(holder) {
		'internal_module', 'module', 'ambient_declaration', 'function_declaration',
		'generator_function_declaration', 'function_expression', 'generator_function',
		'arrow_function', 'method_definition' {
			true
		}
		'class_static_block' {
			parser
		}
		else {
			false
		}
	}
}
