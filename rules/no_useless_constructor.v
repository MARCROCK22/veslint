module rules

import time
import treesitter { has_child_kind, named_children, node_field, node_kind, node_parent }

// Port of the `no-useless-constructor` rule of typescript-eslint 8.62.0 (it has no options), which
// extends the rule of ESLint 10.6.0 with the same name, with its suggestion. The wrapper's checks
// (an accessibility that makes the constructor useful, parameter properties and decorators) are
// also the core rule's.

const nuctor_messages = {
	'noUselessConstructor': 'Useless constructor.'
	'removeConstructor':    'Remove the constructor.'
}

fn (mut c Checker) lint_no_useless_constructor(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut checked := 0
	// A MethodDefinition of kind constructor whose value is a FunctionExpression (not an overload).
	for node in c.nodes_of_kind(root, c'method_definition') {
		body_holder := node_parent(node) or { continue }
		if node_kind(body_holder) != 'class_body' || c.cm_method_kind(node) != 'constructor' {
			continue
		}
		class := node_parent(body_holder) or { continue }
		has_super := if _ := cm_super_class(class) { true } else { false }
		// hasUsefulAccessibility.
		accessibility := c.cm_accessibility(node)
		if accessibility in ['protected', 'private'] || (accessibility == 'public' && has_super) {
			continue
		}
		// hasDecoratorsOrParameterProperty.
		parameters := cm_parameters(node)
		if parameters.any(cm_is_parameter_property(it) || has_child_kind(it, 'decorator')) {
			continue
		}
		body := node_field(node, 'body') or { continue }
		statements := named_children(body)
		checked++
		useless := if has_super {
			c.nuctor_is_redundant_super_call(statements, parameters)
		} else {
			statements.len == 0
		}
		if !useless {
			continue
		}
		// The constructor starts at its decorators, if any; the suggestion removes it, leaving a `;`
		// when the next member would continue the member before it.
		start := cm_start(node)
		end := c.cm_node_end(node)
		mut add_semicolon := false
		if next := c.source_tokens(node).after(end, false) {
			add_semicolon = c.can_continue_expression_in_class_body(next)
				&& c.eslint_needs_preceding_semicolon(node, start)
		}
		_, suggestion := c.suggestion('removeConstructor', map[string]string{}, [
			fix_replace_range(start, end, if add_semicolon { ';' } else { '' }),
		])!
		findings << Finding{
			stmt:        c.position_at(start)
			message_id:  'noUselessConstructor'
			suggestions: [suggestion]
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nuctor_is_redundant_super_call ports isRedundantSuperCall: the body is a single `super(...)` call
// (isSingleSuperCall), the parameters are identifiers or rest elements (isSimple), and the call
// passes `...arguments` or the parameters in order (isPassingThrough).
fn (c &Checker) nuctor_is_redundant_super_call(statements []C.TSNode, parameters []C.TSNode) bool {
	if statements.len != 1 || node_kind(statements[0]) != 'expression_statement' {
		return false
	}
	call := unwrap_parens(first_named(statements[0]) or { return false })
	if node_kind(call) != 'call_expression' {
		return false
	}
	callee := node_field(call, 'function') or { return false }
	if node_kind(callee) != 'super' {
		return false
	}
	arguments := call_arguments(call) or { return false }
	for parameter in parameters {
		kind, _ := nuctor_parameter(parameter)
		if kind !in ['Identifier', 'RestElement'] {
			return false
		}
	}
	return c.nuctor_is_spread_arguments(arguments)
		|| c.nuctor_is_passing_through(parameters, arguments)
}

// nuctor_parameter is the ESTree type of a parameter (Identifier, RestElement, or '' for a pattern
// or a parameter with a default value) and the node of its name or rest argument.
fn nuctor_parameter(parameter C.TSNode) (string, C.TSNode) {
	if _ := node_field(parameter, 'value') {
		return '', parameter
	}
	pattern := node_field(parameter, 'pattern') or { return '', parameter }
	return match node_kind(pattern) {
		'identifier', 'undefined', 'this' { 'Identifier', pattern }
		'rest_pattern' { 'RestElement', first_named(pattern) or { pattern } }
		else { '', pattern }
	}
}

// nuctor_is_spread_arguments ports isSpreadArguments: `super(...arguments)`.
fn (c &Checker) nuctor_is_spread_arguments(arguments []C.TSNode) bool {
	if arguments.len != 1 || node_kind(arguments[0]) != 'spread_element' {
		return false
	}
	argument := unwrap_parens(first_named(arguments[0]) or { return false })
	return node_kind(argument) == 'identifier' && c.identifier_name(argument) == 'arguments'
}

// nuctor_is_passing_through ports isPassingThrough: each parameter goes, in order, as the argument
// of the same name (isValidIdentifierPair), or a rest parameter as the spread of the same name
// (isValidRestSpreadPair).
fn (c &Checker) nuctor_is_passing_through(parameters []C.TSNode, arguments []C.TSNode) bool {
	if parameters.len != arguments.len {
		return false
	}
	for i, parameter in parameters {
		kind, name := nuctor_parameter(parameter)
		mut argument := unwrap_parens(arguments[i])
		if kind == 'RestElement' {
			if node_kind(argument) != 'spread_element' {
				return false
			}
			argument = unwrap_parens(first_named(argument) or { return false })
		}
		if !c.nuctor_is_same_identifier(name, argument) {
			return false
		}
	}
	return true
}

// nuctor_is_same_identifier ports isValidIdentifierPair for a parameter's name and an argument.
fn (c &Checker) nuctor_is_same_identifier(name C.TSNode, argument C.TSNode) bool {
	return node_kind(name) in ['identifier', 'undefined']
		&& node_kind(argument) in ['identifier', 'undefined']
		&& c.identifier_name(name) == c.identifier_name(argument)
}
