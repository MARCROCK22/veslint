module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `logical-assignment-operators` rule of ESLint 10.6.0, with its options, its fixes
// and its suggestions.

const lao_messages = {
	'assignment':         'Assignment (=) can be replaced with operator assignment ({{operator}}).'
	'useLogicalOperator': 'Convert this assignment to use the operator {{ operator }}.'
	'logical':            'Logical expression can be replaced with an assignment ({{ operator }}).'
	'convertLogical':     'Replace this logical expression with an assignment with the operator {{ operator }}.'
	'if':                 "'if' statement can be replaced with a logical operator assignment with operator {{ operator }}."
	'convertIf':          "Replace this 'if' statement with a logical assignment with operator {{ operator }}."
	'unexpected':         'Unexpected logical operator assignment ({{operator}}) shorthand.'
	'separate':           'Separate the logical assignment into an assignment with a logical operator.'
}

struct LaoOptions {
	never    bool
	check_if bool
}

// lao_options reads "always" (with enforceForIfStatements) or "never".
fn lao_options(options []json2.Any) !LaoOptions {
	mode := if options.len > 0 { options[0] } else { json2.Any('always') }
	if mode !is string || mode.str() !in ['always', 'never'] {
		return error('the first option of `${logical_assignment_operators}` must be "always" or "never"')
	}
	o := option_object(logical_assignment_operators, if options.len > 1 {
		options[1..]
	} else {
		[]json2.Any{}
	}, ['enforceForIfStatements'])!
	return LaoOptions{
		never:    mode.str() == 'never'
		check_if: mode.str() == 'always' && (o.bool_value('enforceForIfStatements') or { false })
	}
}

fn (mut c Checker) lint_logical_assignment_operators(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := lao_options(c.rule_options(logical_assignment_operators))!
	mut findings := []Finding{}
	strict := c.lao_is_strict(root)
	kinds := if o.never {
		['augmented_assignment_expression']
	} else {
		['assignment_expression', 'binary_expression', 'if_statement']
	}
	for node in c.nodes_of_kinds(root, kinds, []) {
		stats.checked++
		match node_kind(node) {
			'augmented_assignment_expression' {
				c.lao_never(root, strict, node, mut findings)!
			}
			'assignment_expression' {
				c.lao_assignment(root, strict, node, mut findings)!
			}
			'binary_expression' {
				c.lao_logical(root, strict, node, mut findings)!
			}
			else {
				if o.check_if {
					c.lao_if(root, strict, node, mut findings)!
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// lao_is_strict: the global scope is strict (a "use strict" directive at the start of the file).
fn (c &Checker) lao_is_strict(root C.TSNode) bool {
	for statement in named_children(root) {
		if node_kind(statement) == 'comment' {
			continue
		}
		if node_kind(statement) != 'expression_statement' {
			return false
		}
		expression := first_named(statement) or { return false }
		if node_kind(expression) != 'string' {
			return false
		}
		text := c.text(expression)
		if text[1..text.len - 1] == 'use strict' {
			return true
		}
	}
	return false
}

// lao_inside_with ports isInsideWithBlock: the node is inside the body of a `with`.
fn lao_inside_with(n C.TSNode) bool {
	mut current := n
	for {
		parent := node_parent(current) or { return false }
		if node_kind(parent) == 'with_statement' {
			if body := node_field(parent, 'body') {
				if node_key(body) == node_key(current) {
					return true
				}
			}
		}
		current = parent
	}
	return false
}

fn lao_is_identifier(n C.TSNode) bool {
	return node_kind(n) in ['identifier', 'undefined']
}

// lao_cannot_be_getter ports cannotBeGetter: an identifier outside a `with`.
fn lao_cannot_be_getter(n C.TSNode, strict bool) bool {
	node := unwrap_parens(n)
	return lao_is_identifier(node) && (strict || !lao_inside_with(node))
}

// lao_accesses_single_property ports accessesSingleProperty: one property of an identifier,
// `this` or `super`.
fn lao_accesses_single_property(n C.TSNode, strict bool) bool {
	node := unwrap_parens(n)
	if !strict && lao_inside_with(node) {
		return lao_is_identifier(node)
	}
	if estree_type(node) != 'MemberExpression' {
		return false
	}
	object := unwrap_parens(node_field(node, 'object') or { return false })
	if node_kind(object) !in ['identifier', 'undefined', 'this', 'super'] {
		return false
	}
	if node_kind(node) == 'subscript_expression' {
		index := unwrap_parens(node_field(node, 'index') or { return false })
		return estree_type(index) !in ['MemberExpression', 'ChainExpression']
	}
	return true
}

// lao_is_reference ports isReference: an identifier other than `undefined`, or a member.
fn (c &Checker) lao_is_reference(n C.TSNode) bool {
	node := unwrap_parens(n)
	return (lao_is_identifier(node) && c.identifier_name(node) != 'undefined')
		|| estree_type(node) == 'MemberExpression'
}

// lao_report reports with the changes as a fix when `fixed`, as a suggestion otherwise; no
// change when `fixes` is empty.
fn (mut c Checker) lao_report(node C.TSNode, message_id string, suggestion_id string, operator string, fixes []Fix, fixed bool, mut findings []Finding) ! {
	data := {
		'operator': operator
	}
	mut finding := Finding{
		stmt:       position_of(node)
		message_id: message_id
		data:       data
	}
	if fixes.len > 0 {
		if fixed {
			has_fix, fix := c.merge_fixes(fixes)!
			finding = Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
		} else {
			_, suggestion := c.suggestion(suggestion_id, data, fixes)!
			finding = Finding{
				...finding
				suggestions: [suggestion]
			}
		}
	}
	findings << finding
}

// lao_operator_token is the first token with that text after the node.
fn (mut c Checker) lao_operator_token(root C.TSNode, after C.TSNode, text string) ?SourceToken {
	tokens := c.source_tokens(root)
	mut token := tokens.after(c.es_end(unwrap_parens(after)), false)?
	for c.src[token.start..token.end] != text {
		token = tokens.after(token.end, false)?
	}
	return token
}

fn (mut c Checker) lao_has_comments(root C.TSNode, n C.TSNode) bool {
	return c.source_tokens(root).comments_inside(node_start(n), c.es_end(n)).len > 0
}

fn (mut c Checker) lao_never(root C.TSNode, strict bool, node C.TSNode, mut findings []Finding) ! {
	assignment_operator := operator_of(node)
	if assignment_operator !in ['&&=', '||=', '??='] {
		return
	}
	left := node_field(node, 'left') or { return }
	right := unwrap_parens(node_field(node, 'right') or { return })
	mut fixes := []Fix{}
	if !c.lao_has_comments(root, node) {
		token := c.lao_operator_token(root, left, assignment_operator) or { return }
		operator := assignment_operator[..assignment_operator.len - 1]
		fixes << fix_replace_range(token.start, token.end, '=')
		fixes << fix_insert_at(token.end, ' ${c.es_text(unwrap_parens(left))} ${operator}')
		precedence := es_precedence(right) <= (if operator == '&&' { 5 } else { 4 })
		mixed := assignment_operator == '??=' && estree_binary_kind(right) == 'LogicalExpression'
			&& operator_of(right) in ['&&', '||']
		if !c.es_is_parenthesised(right) && (precedence || mixed) {
			fixes << fix_insert_at(node_start(right), '(')
			fixes << fix_insert_at(c.es_end(right), ')')
		}
	}
	c.lao_report(node, 'unexpected', 'separate', assignment_operator, fixes, lao_cannot_be_getter(left,
		strict), mut findings)!
}

fn (mut c Checker) lao_assignment(root C.TSNode, strict bool, node C.TSNode, mut findings []Finding) ! {
	left := node_field(node, 'left') or { return }
	right := unwrap_parens(node_field(node, 'right') or { return })
	if estree_binary_kind(right) != 'LogicalExpression' {
		return
	}
	operator := operator_of(right)
	// getLeftmostOperand: down the chain of the same operator, to a parenthesised one.
	mut parent := right
	mut operand := unwrap_parens(node_field(right, 'left') or { return })
	for estree_binary_kind(operand) == 'LogicalExpression' && operator_of(operand) == operator {
		if c.es_is_parenthesised(operand) {
			break
		}
		parent = operand
		operand = unwrap_parens(node_field(operand, 'left') or { return })
	}
	if !c.es_is_same_reference(left, operand, false) {
		return
	}
	mut fixes := []Fix{}
	if !c.lao_has_comments(root, node) {
		equals := c.lao_operator_token(root, left, '=') or { return }
		fixes << fix_insert_at(equals.start, operator)
		logical_token := c.lao_operator_token(root, operand, operator) or { return }
		first_right := c.source_tokens(root).after(logical_token.end, false) or { return }
		fixes << fix_remove_range(node_start(parent), first_right.start)
	}
	c.lao_report(node, 'assignment', 'useLogicalOperator', '${operator}=', fixes, lao_cannot_be_getter(left,
		strict), mut findings)!
}

fn (mut c Checker) lao_logical(root C.TSNode, strict bool, node C.TSNode, mut findings []Finding) ! {
	if estree_binary_kind(node) != 'LogicalExpression' {
		return
	}
	left := node_field(node, 'left') or { return }
	right := unwrap_parens(node_field(node, 'right') or { return })
	if node_kind(right) != 'assignment_expression' {
		return
	}
	target := node_field(right, 'left') or { return }
	if !c.lao_is_reference(left) || !c.es_is_same_reference(left, target, false) {
		return
	}
	operator := operator_of(node)
	mut fixes := []Fix{}
	if !c.lao_has_comments(root, node) {
		parent := cti_estree_parent(node) or { node }
		parent_precedence := es_precedence(parent)
		outer := node_kind(parent) != 'expression_statement'
			&& (parent_precedence == -1 || 1 < parent_precedence)
		start := node_start(node)
		end := c.es_end(node)
		if !c.es_is_parenthesised(node) && outer {
			fixes << fix_insert_at(start, '(')
			fixes << fix_insert_at(end, ')')
		}
		fixes << fix_remove_range(start, node_start(right))
		fixes << fix_remove_range(c.es_end(right), end)
		equals := c.lao_operator_token(root, target, '=') or { return }
		fixes << fix_insert_at(equals.start, operator)
	}
	c.lao_report(node, 'logical', 'convertLogical', '${operator}=', fixes, lao_cannot_be_getter(left,
		strict) || lao_accesses_single_property(left, strict), mut findings)!
}

// LaoExistence is what getExistence finds in the test of an if: the reference and the operator.
struct LaoExistence {
	reference C.TSNode
	operator  string
}

// lao_is_undefined ports isUndefined: the global `undefined`, or `void 0`.
fn (mut c Checker) lao_is_undefined(root C.TSNode, n C.TSNode) bool {
	node := unwrap_parens(n)
	if lao_is_identifier(node) && c.identifier_name(node) == 'undefined' {
		return c.es_is_global_reference(root, node)
	}
	if node_kind(node) == 'unary_expression' && operator_of(node) == 'void' {
		argument := unwrap_parens(node_field(node, 'argument') or { return false })
		return c.nic_is_number_value(argument, 0)
	}
	return false
}

// lao_existence ports getExistence.
fn (mut c Checker) lao_existence(root C.TSNode, test C.TSNode) ?LaoExistence {
	expression := unwrap_parens(test)
	negated := node_kind(expression) == 'unary_expression' && operator_of(expression) == '!'
	base := if negated { unwrap_parens(node_field(expression, 'argument')?) } else { expression }
	if c.lao_is_reference(base) {
		return LaoExistence{base, if negated { '||' } else { '&&' }}
	}
	if node_kind(base) == 'unary_expression' && operator_of(base) == '!' {
		argument := unwrap_parens(node_field(base, 'argument')?)
		if c.lao_is_reference(argument) {
			return LaoExistence{argument, '&&'}
		}
	}
	if callee, args := c.es_call_identifier(base) {
		if c.text(callee) == 'Boolean' && args.len == 1 && c.es_is_global_reference(root, callee)
			&& c.lao_is_reference(args[0]) {
			return LaoExistence{unwrap_parens(args[0]), if negated { '||' } else { '&&' }}
		}
	}
	// `x == null`, `x == undefined`.
	if estree_binary_kind(expression) == 'BinaryExpression' && operator_of(expression) == '==' {
		l := unwrap_parens(node_field(expression, 'left')?)
		r := unwrap_parens(node_field(expression, 'right')?)
		reference, nullish := if c.lao_is_reference(l) { l, r } else { r, l }
		if c.lao_is_reference(reference)
			&& (node_kind(nullish) == 'null' || c.lao_is_undefined(root, nullish)) {
			return LaoExistence{reference, '??'}
		}
	}
	// `x === null || x === undefined`.
	if estree_binary_kind(expression) == 'LogicalExpression' && operator_of(expression) == '||' {
		l := unwrap_parens(node_field(expression, 'left')?)
		r := unwrap_parens(node_field(expression, 'right')?)
		if estree_binary_kind(l) == 'BinaryExpression' && operator_of(l) == '==='
			&& estree_binary_kind(r) == 'BinaryExpression' && operator_of(r) == '===' {
			ll := unwrap_parens(node_field(l, 'left')?)
			lr := unwrap_parens(node_field(l, 'right')?)
			rl := unwrap_parens(node_field(r, 'left')?)
			rr := unwrap_parens(node_field(r, 'right')?)
			left_reference, left_nullish := if c.lao_is_reference(ll) { ll, lr } else { lr, ll }
			right_reference, right_nullish := if c.lao_is_reference(rl) { rl, rr } else { rr, rl }
			if c.es_is_same_reference(left_reference, right_reference, false)
				&& ((node_kind(left_nullish) == 'null' && c.lao_is_undefined(root, right_nullish))
					|| (c.lao_is_undefined(root, left_nullish) && node_kind(right_nullish) == 'null')) {
				return LaoExistence{left_reference, '??'}
			}
		}
	}
	return none
}

fn (mut c Checker) lao_if(root C.TSNode, strict bool, node C.TSNode, mut findings []Finding) ! {
	if _ := node_field(node, 'alternative') {
		return
	}
	consequence := node_field(node, 'consequence') or { return }
	has_body := node_kind(consequence) == 'statement_block'
	mut body := consequence
	if has_body {
		statements := named_children(consequence).filter(node_kind(it) != 'comment')
		if statements.len != 1 {
			return
		}
		body = statements[0]
	}
	if node_kind(body) != 'expression_statement' {
		return
	}
	expression := unwrap_parens(first_named(body) or { return })
	if node_kind(expression) != 'assignment_expression' {
		return
	}
	test := node_field(node, 'condition') or { return }
	existence := c.lao_existence(root, test) or { return }
	target := node_field(expression, 'left') or { return }
	if !c.es_is_same_reference(existence.reference, target, false) {
		return
	}
	tokens := c.source_tokens(root)
	mut fixes := []Fix{}
	if !c.lao_has_comments(root, node) {
		first_body := tokens.after(node_start(body), false) or { return }
		mut fixable := true
		if previous := tokens.before(node_start(node), false) {
			text := c.src[previous.start..previous.end]
			if text != ';' && text != '{' && first_body.kind !in [.identifier, .keyword] {
				fixable = false
			}
		}
		if fixable {
			equals := c.lao_operator_token(root, target, '=') or { return }
			fixes << fix_insert_at(equals.start, existence.operator)
			fixes << fix_remove_range(node_start(node), node_start(body))
			end := c.es_end(node)
			body_end := c.es_end(body)
			// Empty without braces, but it still widens the merged fix as in ESLint.
			fixes << fix_remove_range(body_end, end)
			if has_body {
				if next := tokens.after(c.es_end(expression), false) {
					if c.src[next.start..next.end] != ';' {
						fixes << fix_insert_at(end, ';')
					}
				}
			}
		}
	}
	test_node := unwrap_parens(test)
	fixed := lao_cannot_be_getter(existence.reference, strict)
		|| (estree_binary_kind(test_node) != 'LogicalExpression'
			&& lao_accesses_single_property(existence.reference, strict))
	c.lao_report(node, 'if', 'convertIf', '${existence.operator}=', fixes, fixed, mut findings)!
}
