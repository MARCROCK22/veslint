module rules

import json2
import time
import tsgo { TypeResponse }
import treesitter { first_named_child, named_children, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-confusing-void-expression` rule of typescript-eslint 8.62.0, with all its options,
// its fixes and its `voidExprWrapVoid` suggestion.

const ncve_messages = {
	'invalidVoidExpr':               'Placing a void expression inside another expression is forbidden. Move it to its own statement instead.'
	'invalidVoidExprArrow':          'Returning a void expression from an arrow function shorthand is forbidden. Please add braces to the arrow function.'
	'invalidVoidExprArrowWrapVoid':  'Void expressions returned from an arrow function shorthand must be marked explicitly with the `void` operator.'
	'invalidVoidExprReturn':         'Returning a void expression from a function is forbidden. Please move it before the `return` statement.'
	'invalidVoidExprReturnLast':     'Returning a void expression from a function is forbidden. Please remove the `return` statement.'
	'invalidVoidExprReturnWrapVoid': 'Void expressions returned from a function must be marked explicitly with the `void` operator.'
	'invalidVoidExprWrapVoid':       'Void expressions used inside another expression must be moved to its own statement or marked explicitly with the `void` operator.'
	'voidExprWrapVoid':              'Mark with an explicit `void` operator.'
}

// TypeFlags.VoidLike: Undefined | Void.
const ncve_void_like = type_flag_undefined | type_flag_void

// ESTree functions as tree-sitter nodes (a method is its FunctionExpression).
const ncve_function_kinds = ['arrow_function', 'function_declaration', 'function_expression',
	'generator_function', 'generator_function_declaration', 'method_definition']

struct NcveOptions {
	ignore_arrow_shorthand          bool
	ignore_void_operator            bool
	ignore_void_returning_functions bool
}

fn ncve_options(options []json2.Any) !NcveOptions {
	o := option_object(no_confusing_void_expression, options, ['ignoreArrowShorthand',
		'ignoreVoidOperator', 'ignoreVoidReturningFunctions'])!
	return NcveOptions{
		ignore_arrow_shorthand:          o.bool_value('ignoreArrowShorthand')!
		ignore_void_operator:            o.bool_value('ignoreVoidOperator')!
		ignore_void_returning_functions: o.bool_value('ignoreVoidReturningFunctions')!
	}
}

// NcveCandidate is an AwaitExpression, CallExpression or TaggedTemplateExpression in an invalid
// position (findInvalidAncestor), with that ancestor.
struct NcveCandidate {
	node     C.TSNode
	ancestor C.TSNode
}

fn (mut c Checker) lint_no_confusing_void_expression(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := ncve_options(c.rule_options(no_confusing_void_expression))!
	mut candidates := []NcveCandidate{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['await_expression', 'call_expression'], []string{}) {
		if node_kind(node) == 'call_expression' {
			// `import(…)` is an ImportExpression in ESTree.
			callee := node_field(node, 'function') or { continue }
			if node_kind(callee) == 'import' {
				continue
			}
		}
		ancestor := c.ncve_invalid_ancestor(node, o, 0) or { continue }
		candidates << NcveCandidate{
			node:     node
			ancestor: ancestor
		}
		spans << node_span(node)
		// canFix looks at the type of the arrow function's body or of the returned value.
		if target := ncve_fix_target(ancestor) {
			spans << node_span(target)
		}
		if o.ignore_void_returning_functions {
			function := if node_kind(ancestor) == 'arrow_function' {
				ancestor
			} else if node_kind(ancestor) == 'return_statement' {
				ncve_parent_function(ancestor) or { continue }
			} else {
				continue
			}
			spans << ncve_function_span(function)
			if annotation := node_field(function, 'return_type') {
				if type_node := first_named(annotation) {
					spans << c.type_node_span(unwrap_type_parens(type_node))
				}
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for cand in candidates {
		// Outside an async function TypeScript may read `await [x]` as an element access, which is
		// not one of the visited nodes.
		if node_kind(cand.node) == 'await_expression'
			&& c.await_reading(cand.node) !in [.await_expr, .call, .tagged_template] {
			continue
		}
		t := c.node_type(cand.node) or { continue }
		if c.constrained(t)!.flags & ncve_void_like == 0 {
			continue
		}
		message_id := c.ncve_message(cand, o)!
		if message_id == '' {
			continue
		}
		finding := Finding{
			stmt:       position_of(cand.node)
			message_id: message_id
		}
		// wrapVoidFix: `void ` before the void expression.
		wrap_void := [fix_replace(cand.node, 'void ${c.text(cand.node)}')]
		match message_id {
			'invalidVoidExprArrowWrapVoid', 'invalidVoidExprReturnWrapVoid' {
				findings << c.with_fixes(finding, wrap_void)!
			}
			'invalidVoidExprWrapVoid' {
				_, suggestion := c.suggestion('voidExprWrapVoid', map[string]string{}, wrap_void)!
				findings << Finding{
					...finding
					suggestions: [suggestion]
				}
			}
			'invalidVoidExprArrow' {
				findings << c.with_fixes(finding, c.ncve_arrow_fix(cand.ancestor)!)!
			}
			'invalidVoidExprReturnLast' {
				findings << c.with_fixes(finding, c.ncve_return_last_fix(cand.ancestor)!)!
			}
			'invalidVoidExprReturn' {
				findings << c.with_fixes(finding, c.ncve_return_fix(cand.ancestor))!
			}
			else {
				findings << finding
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

// ncve_fix_target is the node canFix asks the type of: the body of an arrow function or the
// argument of a return statement, without parentheses.
fn ncve_fix_target(ancestor C.TSNode) ?C.TSNode {
	return match node_kind(ancestor) {
		'arrow_function' { unwrap_parens(node_field(ancestor, 'body')?) }
		'return_statement' { unwrap_parens(first_named_child(ancestor)?) }
		else { none }
	}
}

// ncve_can_fix ports canFix: the body or the returned value is void (not, for instance, the
// `false | void` of `cond && f()`).
fn (mut c Checker) ncve_can_fix(ancestor C.TSNode) !bool {
	target := ncve_fix_target(ancestor) or { return false }
	t := c.node_type(target) or { return false }
	return c.constrained(t)!.flags & ncve_void_like != 0
}

// ncve_arrow_fix ports the fixer of `invalidVoidExprArrow`: the body becomes `{ body; }`, replacing
// its closest parentheses if it has them. No fix if the body is not void.
fn (mut c Checker) ncve_arrow_fix(arrow C.TSNode) ![]Fix {
	if !c.ncve_can_fix(arrow)! {
		return []Fix{}
	}
	body := ncve_fix_target(arrow) or { return []Fix{} }
	text := '{ ${c.text(body)}; }'
	if wrapper := node_parent(body) {
		if node_kind(wrapper) == 'parenthesized_expression' {
			return [fix_replace(wrapper, text)]
		}
	}
	return [fix_replace(body, text)]
}

// ncve_return_last_fix ports the fixer of `invalidVoidExprReturnLast`: the statement becomes its
// value. No fix if the value is not void.
fn (mut c Checker) ncve_return_last_fix(statement C.TSNode) ![]Fix {
	if !c.ncve_can_fix(statement)! {
		return []Fix{}
	}
	value := ncve_fix_target(statement) or { return []Fix{} }
	return [fix_replace(statement, '${c.ncve_asi_guard(value)}${c.text(value)};')]
}

// ncve_return_fix ports the fixer of `invalidVoidExprReturn`: the value moves before a bare
// `return;`, in braces if the statement is not in a block.
fn (c &Checker) ncve_return_fix(statement C.TSNode) []Fix {
	value := ncve_fix_target(statement) or { return []Fix{} }
	mut text := '${c.ncve_asi_guard(value)}${c.text(value)}; return;'
	in_block := if parent := node_parent(statement) {
		node_kind(parent) == 'statement_block'
	} else {
		false
	}
	if !in_block {
		text = '{ ${text} }'
	}
	return [fix_replace(statement, text)]
}

// ncve_asi_guard ports isPreventingASI: `;` when the first token of the value is `(` or `[`, which
// on its own line would continue the previous statement.
fn (c &Checker) ncve_asi_guard(value C.TSNode) string {
	start := node_start(value)
	return if start < c.src.len && c.src[start] in [`(`, `[`] { ';' } else { '' }
}

// ncve_message picks the message for a void expression in an invalid position ('' when an option
// makes it valid).
fn (mut c Checker) ncve_message(cand NcveCandidate, o NcveOptions) !string {
	ancestor := cand.ancestor
	match node_kind(ancestor) {
		'arrow_function' {
			if o.ignore_void_returning_functions && c.ncve_void_returning(ancestor)! {
				return ''
			}
			return if o.ignore_void_operator {
				'invalidVoidExprArrowWrapVoid'
			} else {
				'invalidVoidExprArrow'
			}
		}
		'return_statement' {
			if o.ignore_void_returning_functions {
				if function := ncve_parent_function(ancestor) {
					if c.ncve_void_returning(function)! {
						return ''
					}
				}
			}
			if o.ignore_void_operator {
				return 'invalidVoidExprReturnWrapVoid'
			}
			return if ncve_is_final_return(ancestor) {
				'invalidVoidExprReturnLast'
			} else {
				'invalidVoidExprReturn'
			}
		}
		else {
			return if o.ignore_void_operator {
				'invalidVoidExprWrapVoid'
			} else {
				'invalidVoidExpr'
			}
		}
	}
}

// ncve_invalid_ancestor ports findInvalidAncestor: none when the void expression is in a valid
// position, else the closest invalid ESTree ancestor. Parentheses are not ESTree nodes and the
// ChainExpression around an optional chain is transparent.
fn (c &Checker) ncve_invalid_ancestor(node C.TSNode, o NcveOptions, depth int) ?C.TSNode {
	parent := estree_parent(node)?
	if depth >= max_expression_depth {
		return none
	}
	match node_kind(parent) {
		'sequence_expression' {
			expressions := named_children(parent)
			if expressions.len > 0 && node_key(unwrap_parens(expressions.last())) != node_key(node) {
				return none
			}
		}
		'expression_statement' {
			return none
		}
		'binary_expression' {
			if estree_binary_kind(parent) == 'LogicalExpression' {
				if right := node_field(parent, 'right') {
					if node_key(unwrap_parens(right)) == node_key(node) {
						return c.ncve_invalid_ancestor(parent, o, depth + 1)
					}
				}
			}
		}
		'ternary_expression' {
			for field in ['consequence', 'alternative'] {
				if branch := node_field(parent, field) {
					if node_key(unwrap_parens(branch)) == node_key(node) {
						return c.ncve_invalid_ancestor(parent, o, depth + 1)
					}
				}
			}
		}
		'arrow_function' {
			if o.ignore_arrow_shorthand {
				return none
			}
		}
		'unary_expression' {
			if operator_of(parent) == 'void' && o.ignore_void_operator {
				return none
			}
		}
		else {}
	}
	return parent
}

// ncve_is_final_return ports isFinalReturn: the last statement of the block of a function.
fn ncve_is_final_return(statement C.TSNode) bool {
	block := node_parent(statement) or { return false }
	if node_kind(block) != 'statement_block' {
		return false
	}
	function := node_parent(block) or { return false }
	if node_kind(function) !in ncve_function_kinds {
		return false
	}
	statements := named_children(block)
	return statements.len > 0 && node_key(statements.last()) == node_key(statement)
}

// ncve_parent_function ports getParentFunctionNode: the closest enclosing function.
fn ncve_parent_function(n C.TSNode) ?C.TSNode {
	mut current := node_parent(n)?
	for depth := 0; depth < max_expression_depth; depth++ {
		if node_kind(current) in ncve_function_kinds {
			return current
		}
		current = node_parent(current)?
	}
	return none
}

// ncve_function_span is the tsgo node of a function, for its contextual type (a class method also
// covers its decorators).
fn ncve_function_span(function C.TSNode) Span {
	return if node_kind(function) == 'method_definition' {
		member_span(function)
	} else {
		node_span(function)
	}
}

// ncve_void_returning ports isVoidReturningFunctionNode: the return type annotation includes `void`
// or, for a function that is not a declaration, its contextual type has a call signature whose
// return type includes `void` (tsutils.isIntrinsicVoidType: the own flags).
fn (mut c Checker) ncve_void_returning(function C.TSNode) !bool {
	if annotation := node_field(function, 'return_type') {
		type_node := unwrap_type_parens(first_named(annotation) or { return false })
		return_type := c.node_type(type_node) or { return false }
		return c.constituents(return_type)!.any(it.flags & type_flag_void != 0)
	}
	if node_kind(function) in ['function_declaration', 'generator_function_declaration'] {
		return false
	}
	function_type := c.contextual_type(function)!
	if function_type.is_null() {
		return false
	}
	for part in c.constituents(function_type)! {
		if c.ncve_returns_void(part)! {
			return true
		}
	}
	return false
}

// ncve_returns_void ports isFunctionReturnTypeIncludesVoid.
fn (mut c Checker) ncve_returns_void(t TypeResponse) !bool {
	for sig in c.call_signatures_of(t)! {
		if c.constituents(c.return_type(sig.id)!)!.any(it.flags & type_flag_void != 0) {
			return true
		}
	}
	return false
}
