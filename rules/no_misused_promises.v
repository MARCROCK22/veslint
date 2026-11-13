module rules

import json2
import time
import tsgo { ParameterResponse, SymbolResponse, TypeResponse }
import treesitter { Ident, first_named_child, has_child_kind, named_children, next_sibling, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kind, position_of, prev_sibling }

// Port of the `no-misused-promises` rule of typescript-eslint 8.62.0 with its default options:
// checksConditionals, checksSpreads and checksVoidReturn (arguments, properties, return values,
// variables and inherited methods; not JSX attributes, since veslint does not read .tsx). Limits
// of the port: README, "Rules" section.

const nmp_messages = {
	'conditional':               'Expected non-Promise value in a boolean conditional.'
	'predicate':                 'Expected a non-Promise value to be returned.'
	'spread':                    'Expected a non-Promise value to be spread in an object.'
	'voidReturnArgument':        'Promise returned in function argument where a void return was expected.'
	'voidReturnAttribute':       'Promise-returning function provided to attribute where a void return was expected.'
	'voidReturnInheritedMethod': "Promise-returning method provided where a void return was expected by extended/implemented type '{{ heritageTypeName }}'."
	'voidReturnProperty':        'Promise-returning function provided to property where a void return was expected.'
	'voidReturnReturnValue':     'Promise-returning function provided to return value where a void return was expected.'
	'voidReturnVariable':        'Promise-returning function provided to variable where a void return was expected.'
}

// Array methods whose callback is a predicate (ARRAY_PREDICATE_FUNCTIONS).
const array_predicate_methods = ['every', 'filter', 'find', 'findIndex', 'findLast', 'findLastIndex',
	'some']

const logical_operators = ['&&', '||', '??']

// Bit that tells heritage spans (`extends X<T>`) apart from nodes in node_types.
const heritage_key_bit = u64(1) << 63

// Member is a named member of a class or interface with heritage.
struct Member {
	span Span // from its first decorator to its `;`, like the TypeScript node
	name string
}

struct ClassLike {
	heritage []Span
	members  []Member
}

struct MisusedTargets {
mut:
	conditions  []C.TSNode // values used as a condition
	predicates  []C.TSNode // calls to a predicate method (`x.filter(cb)`)
	calls       []C.TSNode // calls and `new` with arguments
	variables   []C.TSNode // variable_declarator with a value and an annotation that may be a function
	assignments []C.TSNode
	properties  []C.TSNode // properties of object literals
	attributes  []C.TSNode // the `{…}` value of JSX attributes, with an expression inside
	returns     []C.TSNode // return_statement with a value
	classes     []ClassLike
	spreads     []C.TSNode
}

// NmpOptions are the checks the options turn on: checksConditionals, checksSpreads and the parts
// of checksVoidReturn (parseChecksVoidReturn).
struct NmpOptions {
	conditionals      bool
	spreads           bool
	arguments         bool
	attributes        bool
	inherited_methods bool
	properties        bool
	returns           bool
	variables         bool
}

const nmp_void_return_keys = ['arguments', 'attributes', 'inheritedMethods', 'properties', 'returns',
	'variables']

fn nmp_options(options []json2.Any) !NmpOptions {
	o := option_object(no_misused_promises, options, ['checksConditionals', 'checksSpreads',
		'checksVoidReturn'])!
	// checksVoidReturn: false, true, or an object whose missing keys are true.
	mut parts := map[string]bool{}
	for key in nmp_void_return_keys {
		parts[key] = true
	}
	void_return := o.values['checksVoidReturn'] or { json2.Any(true) }
	if void_return is bool {
		for key in nmp_void_return_keys {
			parts[key] = void_return
		}
	} else if void_return is map[string]json2.Any {
		for key, value in void_return {
			if key !in nmp_void_return_keys {
				return error('unknown key `${key}` in option `checksVoidReturn` of `${no_misused_promises}`')
			}
			if value !is bool {
				return error('`${key}` in option `checksVoidReturn` of `${no_misused_promises}` must be true or false')
			}
			parts[key] = value as bool
		}
	} else {
		return error('option `checksVoidReturn` of `${no_misused_promises}` must be true, false or an object')
	}
	return NmpOptions{
		conditionals:      o.bool_value('checksConditionals')!
		spreads:           o.bool_value('checksSpreads')!
		arguments:         parts['arguments']
		attributes:        parts['attributes']
		inherited_methods: parts['inheritedMethods']
		properties:        parts['properties']
		returns:           parts['returns']
		variables:         parts['variables']
	}
}

fn (mut c Checker) lint_no_misused_promises(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nmp_options(c.rule_options(no_misused_promises))!
	mut t := MisusedTargets{}
	if o.conditionals {
		t.conditions = c.conditional_operands(root)
	}
	for call in c.nodes_of_kind(root, c'call_expression') {
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		if o.conditionals {
			if name := c.static_member_string(callee) {
				if name in array_predicate_methods {
					t.predicates << call
				}
			}
		}
		// `import(…)` is an ImportExpression in ESTree, not a call.
		if node_kind(callee) == 'import' {
			continue
		}
		if o.arguments {
			if _ := call_args(call) {
				t.calls << call
			}
		}
	}
	if o.arguments {
		for call in c.nodes_of_kind(root, c'new_expression') {
			if _ := call_args(call) {
				t.calls << call
			}
		}
	}
	if o.variables {
		for decl in c.nodes_of_kind(root, c'variable_declarator') {
			if _ := node_field(decl, 'value') {
				annotation := node_field(decl, 'type') or { continue }
				if is_possibly_function_type(annotation) {
					t.variables << decl
				}
			}
		}
		t.assignments << c.nodes_of_kind(root, c'assignment_expression')
		t.assignments << c.nodes_of_kind(root, c'augmented_assignment_expression')
	}
	if o.properties {
		for object in c.nodes_of_kind(root, c'object') {
			for prop in named_children(object) {
				if node_kind(prop) in ['pair', 'shorthand_property_identifier', 'method_definition'] {
					t.properties << prop
				}
			}
		}
	}
	if o.attributes {
		// JSXAttribute whose value is a JSXExpressionContainer (with an expression: `{}` and
		// `{/* c */}` hold a JSXEmptyExpression, which returns nothing).
		for attribute in c.nodes_of_kind(root, c'jsx_attribute') {
			for child in named_children(attribute) {
				if node_kind(child) == 'jsx_expression' && jsx_expression_value(child) != none {
					t.attributes << child
				}
			}
		}
	}
	if o.returns {
		for ret in c.nodes_of_kind(root, c'return_statement') {
			if _ := first_named_child(ret) {
				t.returns << ret
			}
		}
	}
	if o.inherited_methods {
		mut class_nodes := []C.TSNode{}
		class_nodes << c.nodes_of_kind(root, c'class_declaration')
		class_nodes << c.nodes_of_kind(root, c'abstract_class_declaration')
		class_nodes << c.nodes_of_kind(root, c'class')
		class_nodes << c.nodes_of_kind(root, c'interface_declaration')
		for node in class_nodes {
			class_like := c.class_like(node)
			if class_like.heritage.len > 0 {
				t.classes << class_like
			}
		}
	}
	if o.spreads {
		// ESTree's SpreadElement: the spread of a JSX attribute or of a JSX child is another node
		// (JSXSpreadAttribute, JSXSpreadChild), which the rule does not listen to.
		t.spreads = c.nodes_of_kind(root, c'spread_element').filter(!is_jsx_spread(it))
	}
	c.resolve_spans(misused_spans(t), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	findings := c.check_no_misused_promises(t)!
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += t.conditions.len + t.predicates.len + t.calls.len + t.variables.len +
		t.assignments.len + t.properties.len + t.attributes.len + t.returns.len + t.classes.len +
		t.spreads.len
	return findings
}

// misused_spans are the nodes whose type (or contextual type) may be needed.
fn misused_spans(t MisusedTargets) []Span {
	mut nodes := []C.TSNode{}
	nodes << t.conditions
	for call in t.predicates {
		callee := unwrap_parens(node_field(call, 'function') or { continue })
		if object := node_field(callee, 'object') {
			nodes << object
		}
		args := call_args(call) or { continue }
		if args.len > 0 {
			nodes << unwrap_parens(args[0])
		}
	}
	for call in t.calls {
		if callee := call_callee(call) {
			nodes << callee
			if object := node_field(unwrap_parens(callee), 'object') {
				nodes << object
			}
		}
		args := call_args(call) or { []C.TSNode{} }
		for arg in args {
			nodes << arg
			nodes << unwrap_parens(arg)
		}
		// The signature of the call is asked when a spread may shift its arguments
		// (contextual_argument_type).
		if args.any(node_kind(it) == 'spread_element') {
			nodes << call
		}
	}
	for decl in t.variables {
		if name := node_field(decl, 'name') {
			nodes << name
		}
		if value := node_field(decl, 'value') {
			nodes << value
		}
	}
	for a in t.assignments {
		if left := node_field(a, 'left') {
			nodes << left
		}
		if right := node_field(a, 'right') {
			nodes << right
		}
	}
	for prop in t.properties {
		match node_kind(prop) {
			'pair' {
				if value := node_field(prop, 'value') {
					nodes << value
				}
			}
			'shorthand_property_identifier' {
				nodes << prop
			}
			else {}
		}
	}
	for container in t.attributes {
		nodes << container
		if value := jsx_expression_value(container) {
			nodes << value
		}
	}
	for ret in t.returns {
		if expr := first_named_child(ret) {
			nodes << expr
		}
	}
	for spread in t.spreads {
		if expr := first_named_child(spread) {
			nodes << expr
		}
	}
	mut spans := nodes.map(node_span(it))
	// Object methods and their object literal are requested by SyntaxKind: they share a range with
	// other nodes.
	for prop in t.properties {
		if node_kind(prop) == 'method_definition' && !has_child_kind(prop, 'get')
			&& !has_child_kind(prop, 'set') {
			spans << Span{
				key:   node_key(prop)
				first: prop
				end:   node_end(prop)
				kind:  syntax_kind_method_declaration
			}
			if object := node_parent(prop) {
				spans << Span{
					key:   node_key(object)
					first: object
					end:   node_end(object)
					kind:  syntax_kind_object_literal_expression
				}
			}
			// The name is where the type of the property is asked (getTypeOfSymbolAtLocation).
			if name := node_field(prop, 'name') {
				spans << Span{
					...node_span(name)
					optional: true
				}
			}
		}
	}
	for class_like in t.classes {
		spans << class_like.heritage
		spans << class_like.members.map(it.span)
	}
	return spans
}

fn (mut c Checker) check_no_misused_promises(t MisusedTargets) ![]Finding {
	mut findings := []Finding{}
	// checksConditionals
	for node in t.conditions {
		if c.is_always_thenable(node)! {
			findings << finding_at(node, 'conditional')
		}
	}
	for call in t.predicates {
		callback := c.array_predicate_callback(call)!
		if callback.len == 1 && c.returns_thenable(callback[0])! {
			// The `CallExpression > MemberExpression` selector fires once for each MemberExpression child of
			// the call, and typescript-eslint reports each time.
			for _ in 0 .. member_children(call) {
				findings << finding_at(callback[0], 'predicate')
			}
		}
	}
	// checksVoidReturn
	for call in t.calls {
		args := call_args(call) or { continue }
		if c.is_promise_finally_call(call)! {
			continue
		}
		mut thenable_args := []int{}
		for i, arg in args {
			if c.returns_thenable(unwrap_parens(arg))! {
				thenable_args << i
			}
		}
		if thenable_args.len == 0 {
			continue
		}
		void_args := c.void_function_arguments(call, args)!
		for i in thenable_args {
			if i in void_args {
				findings << finding_at(unwrap_parens(args[i]), 'voidReturnArgument')
			}
		}
	}
	for decl in t.variables {
		name := node_field(decl, 'name') or { continue }
		value := node_field(decl, 'value') or { continue }
		var_type := c.node_type(name) or { continue }
		if c.is_void_returning_function_type(var_type, c.symbol_location(value))!
			&& c.returns_thenable(value)! {
			findings << finding_at(unwrap_parens(value), 'voidReturnVariable')
		}
	}
	for a in t.assignments {
		left := node_field(a, 'left') or { continue }
		right := node_field(a, 'right') or { continue }
		var_type := c.node_type(left) or { continue }
		if c.is_void_returning_function_type(var_type, c.symbol_location(left))!
			&& c.returns_thenable(right)! {
			findings << finding_at(unwrap_parens(right), 'voidReturnVariable')
		}
	}
	for prop in t.properties {
		position := c.misused_property(prop)!
		if position.len == 1 {
			findings << Finding{
				stmt:       position[0]
				message_id: 'voidReturnProperty'
			}
		}
	}
	// checkJSXAttribute: the contextual type of the container is a void-returning function and
	// the expression returns a thenable.
	for container in t.attributes {
		value := jsx_expression_value(container) or { continue }
		contextual := c.contextual_type(container)!
		if !contextual.is_null()
			&& c.is_void_returning_function_type(contextual, c.symbol_location(container))!
			&& c.returns_thenable(value)! {
			findings << finding_at(container, 'voidReturnAttribute')
		}
	}
	for ret in t.returns {
		expr := first_named_child(ret) or { continue }
		f := enclosing_function(ret) or { continue }
		if return_type := node_field(f, 'return_type') {
			if !is_possibly_function_type(return_type) {
				continue
			}
		}
		if !c.returns_thenable(expr)! {
			continue
		}
		contextual := c.contextual_type(expr)!
		if !contextual.is_null()
			&& c.is_void_returning_function_type(contextual, c.symbol_location(expr))! {
			findings << finding_at(unwrap_parens(expr), 'voidReturnReturnValue')
		}
	}
	for class_like in t.classes {
		findings << c.inherited_method_findings(class_like)!
	}
	// checksSpreads
	for spread in t.spreads {
		expr := first_named_child(spread) or { continue }
		if c.is_sometimes_thenable(expr)! {
			findings << finding_at(unwrap_parens(expr), 'spread')
		}
	}
	findings.sort_with_compare(compare_findings)
	return findings
}

// is_jsx_spread tells whether a spread is the one of a JSX attribute (`<a {...x} />`) or of a JSX
// child (`<a>{...x}</a>`).
fn is_jsx_spread(spread C.TSNode) bool {
	parent := node_parent(spread) or { return false }
	return node_kind(parent) == 'jsx_expression'
}

fn finding_at(node C.TSNode, message_id string) Finding {
	return Finding{
		stmt:       position_of(node)
		message_id: message_id
	}
}

// compare_findings orders by position and, at the same position, stably across runs.
fn compare_findings(a &Finding, b &Finding) int {
	if a.stmt.start_byte != b.stmt.start_byte {
		return if a.stmt.start_byte < b.stmt.start_byte { -1 } else { 1 }
	}
	key_a := '${a.message_id}\t${a.data.values().join('\t')}'
	key_b := '${b.message_id}\t${b.data.values().join('\t')}'
	if key_a == key_b {
		return 0
	}
	return if key_a < key_b { -1 } else { 1 }
}

// conditional_operands ports the checksConditionals handlers (checkTestConditional and
// checkConditional): the values used as a condition, without repeating any.
fn (mut c Checker) conditional_operands(root C.TSNode) []C.TSNode {
	mut checked := map[u64]bool{}
	mut out := []C.TSNode{}
	// First the conditions (test of if, while, do, for and ?:, and the operand of `!`): they are
	// ancestors of the logical expressions they contain and ESLint visits them first.
	mut tests := []C.TSNode{}
	tests << c.nodes_of_kind(root, c'if_statement')
	tests << c.nodes_of_kind(root, c'while_statement')
	tests << c.nodes_of_kind(root, c'do_statement')
	tests << c.nodes_of_kind(root, c'ternary_expression')
	tests << c.nodes_of_kind(root, c'for_statement')
	for node in tests {
		if test := node_field(node, 'condition') {
			if node_kind(test) !in [';', 'empty_statement'] {
				c.check_conditional(test, true, 0, mut checked, mut out)
			}
		}
	}
	for node in c.nodes_of_kind(root, c'unary_expression') {
		if operator_of(node) == '!' {
			if arg := node_field(node, 'argument') {
				c.check_conditional(arg, true, 0, mut checked, mut out)
			}
		}
	}
	// Then every logical expression not seen yet, outside a condition.
	for node in c.nodes_of_kind(root, c'binary_expression') {
		if operator_of(node) in logical_operators {
			c.check_conditional(node, false, 0, mut checked, mut out)
		}
	}
	return out
}

// check_conditional ports checkConditional: of a logical expression it checks the left side
// (except for `??` outside a condition) and, inside a condition, the right side too.
fn (mut c Checker) check_conditional(n C.TSNode, is_test bool, depth int, mut checked map[u64]bool, mut out []C.TSNode) {
	if depth > max_expression_depth {
		c.too_deep++
		return
	}
	node := unwrap_parens(n)
	key := node_key(node)
	if key in checked {
		return
	}
	checked[key] = true
	if node_kind(node) == 'binary_expression' && operator_of(node) in logical_operators {
		if operator_of(node) != '??' || is_test {
			if left := node_field(node, 'left') {
				c.check_conditional(left, is_test, depth + 1, mut checked, mut out)
			}
		}
		if is_test {
			if right := node_field(node, 'right') {
				c.check_conditional(right, is_test, depth + 1, mut checked, mut out)
			}
		}
		return
	}
	out << node
}

// call_args are the arguments of a call or a `new` (not of a tagged template nor of a `new X`
// without parentheses).
fn call_args(call C.TSNode) ?[]C.TSNode {
	args := node_field(call, 'arguments')?
	if node_kind(args) != 'arguments' {
		return none
	}
	return named_children(args)
}

fn call_callee(call C.TSNode) ?C.TSNode {
	field := if node_kind(call) == 'new_expression' { 'constructor' } else { 'function' }
	return node_field(call, field)
}

// member_children counts the MemberExpression children of a call in ESTree: the callee and the
// arguments that are member accesses.
fn member_children(call C.TSNode) int {
	mut count := 1
	for arg in call_args(call) or { []C.TSNode{} } {
		if node_kind(unwrap_parens(arg)) in ['member_expression', 'subscript_expression'] {
			count++
		}
	}
	return count
}

// array_predicate_callback ports isArrayMethodCallWithPredicate and returns the first argument of
// `x.filter(…)` and the like when x is an array or a tuple (empty list otherwise).
fn (mut c Checker) array_predicate_callback(call C.TSNode) ![]C.TSNode {
	callee := unwrap_parens(node_field(call, 'function') or { return []C.TSNode{} })
	object := node_field(callee, 'object') or { return []C.TSNode{} }
	args := call_args(call) or { return []C.TSNode{} }
	if args.len == 0 {
		return []C.TSNode{}
	}
	object_type := c.node_type(object) or { return []C.TSNode{} }
	for part in c.constituents(c.constrained(object_type)!)! {
		for inner in c.intersection_parts(part)! {
			if c.is_array(inner)! || c.is_tuple(inner)! {
				return [unwrap_parens(args[0])]
			}
		}
	}
	return []C.TSNode{}
}

fn (mut c Checker) intersection_parts(t TypeResponse) ![]TypeResponse {
	if t.flags & type_flag_intersection != 0 {
		return c.members_of(t)!
	}
	return [t]
}

// is_promise_finally_call ports isPromiseFinallyMethod: `p.finally(…)` with p a Promise.
fn (mut c Checker) is_promise_finally_call(call C.TSNode) !bool {
	if node_kind(call) != 'call_expression' {
		return false
	}
	callee := unwrap_parens(node_field(call, 'function') or { return false })
	if (c.static_member_string(callee) or { '' }) != 'finally' {
		return false
	}
	object := node_field(callee, 'object') or { return false }
	t := c.node_type(object) or { return false }
	return c.builtin_promise(c.constrained(t)!, 0)!
}

// void_function_arguments ports voidFunctionArguments: the indexes of the arguments that take a
// void-returning function (and not also a promise-returning one), looking at all the signatures
// of the type of the callee.
fn (mut c Checker) void_function_arguments(call C.TSNode, args []C.TSNode) ![]int {
	callee := call_callee(call) or { return []int{} }
	callee_type := c.node_type(callee) or { return []int{} }
	kind := if node_kind(call) == 'new_expression' {
		signature_kind_construct
	} else {
		signature_kind_call
	}
	mut indices := VoidArguments{
		call: call
		args: args
		// The callee is the node the types are asked at (`node.expression`).
		at:   c.symbol_location(callee)
	}
	for sub in c.constituents(callee_type)! {
		for sig in c.signatures_of(sub, kind)! {
			params := c.signature_parameters(sig)!
			for index, param in params {
				param_type := c.parameter_type_at(param, indices.at)!
				is_rest := sig.flags & signature_flag_has_rest_parameter != 0
					&& index == params.len - 1
				if !is_rest {
					c.check_thenable_or_void(param_type, index, mut indices)!
				} else if c.is_array(param_type)! {
					element := c.client.type_arguments(c.snapshot, c.project, param_type.id)!
					if element.len > 0 {
						for i in index .. args.len {
							c.check_thenable_or_void(element[0], i, mut indices)!
						}
					}
				} else if c.is_tuple(param_type)! {
					elements := c.client.type_arguments(c.snapshot, c.project, param_type.id)!
					for i := index; i < args.len && i - index < elements.len; i++ {
						c.check_thenable_or_void(elements[i - index], i, mut indices)!
					}
				}
			}
		}
	}
	mut out := []int{}
	for index, _ in indices.void {
		if index !in indices.thenable {
			out << index
		}
	}
	return out
}

// VoidArguments is the state of voidFunctionArguments for a call: its arguments, the node the
// types are asked at and the indexes found so far (thenableReturnIndices and voidReturnIndices).
struct VoidArguments {
	call C.TSNode
	args []C.TSNode
	at   SymbolLocation
mut:
	thenable map[int]bool
	void     map[int]bool
}

// check_thenable_or_void ports checkThenableOrVoidArgument. Without an argument at that index
// there is nothing to report.
fn (mut c Checker) check_thenable_or_void(t TypeResponse, index int, mut indices VoidArguments) ! {
	if index >= indices.args.len {
		return
	}
	if c.is_thenable_returning_function_type(t, indices.at)! {
		indices.thenable[index] = true
	} else if c.is_void_returning_function_type(t, indices.at)! && index !in indices.thenable {
		indices.void[index] = true
	}
	contextual := c.contextual_argument_type(indices.call, indices.args, index)!
	if !contextual.is_null() && contextual.id != t.id {
		c.check_thenable_or_void(contextual, index, mut indices)!
	}
}

// misused_property ports checkProperty and returns where to report (empty list when it should
// not).
fn (mut c Checker) misused_property(prop C.TSNode) ![]Ident {
	match node_kind(prop) {
		'pair' {
			value := node_field(prop, 'value') or { return []Ident{} }
			if !c.returns_thenable(value)! {
				return []Ident{}
			}
			contextual := c.contextual_type(value)!
			if contextual.is_null()
				|| !c.is_void_returning_function_type(contextual, c.symbol_location(value))! {
				return []Ident{}
			}
			return [c.function_report_position(unwrap_parens(value))]
		}
		'shorthand_property_identifier' {
			if !c.returns_thenable(prop)! {
				return []Ident{}
			}
			contextual := c.contextual_type(prop)!
			if contextual.is_null()
				|| !c.is_void_returning_function_type(contextual, c.symbol_location(prop))! {
				return []Ident{}
			}
			return [position_of(prop)]
		}
		else {
			// A method: not computed keys nor get/set (they are not a MethodDeclaration).
			name := node_field(prop, 'name') or { return []Ident{} }
			if node_kind(name) == 'computed_property_name' || has_child_kind(prop, 'get')
				|| has_child_kind(prop, 'set') {
				return []Ident{}
			}
			if !c.returns_thenable(prop)! {
				return []Ident{}
			}
			object := node_parent(prop) or { return []Ident{} }
			object_type := c.contextual_type(object)!
			if object_type.is_null() {
				return []Ident{}
			}
			mut property := SymbolResponse{}
			for part in c.constituents(object_type)! {
				property = c.property(part, c.text(name))!
				if !property.is_null() {
					break
				}
			}
			if property.is_null() {
				return []Ident{}
			}
			// getTypeOfSymbolAtLocation(propertySymbol, tsNode.name)
			at := c.symbol_location(name)
			if !c.is_void_returning_function_type(c.symbol_type_at(property, at)!, at)! {
				return []Ident{}
			}
			return [c.function_report_position(prop)]
		}
	}
}

// function_report_position: a function is reported at its annotated return type or, without one,
// at the start of getFunctionHeadLoc; any other value, at its start.
fn (mut c Checker) function_report_position(value C.TSNode) Ident {
	if node_kind(value) !in ['arrow_function', 'function_expression', 'generator_function',
		'method_definition'] {
		return position_of(value)
	}
	if return_type := node_field(value, 'return_type') {
		if annotated := first_named_child(return_type) {
			return position_of(annotated)
		}
	}
	return c.function_head(value)
}

// is_possibly_function_type ports isPossiblyFunctionType on a type annotation: a syntactic check
// that rules out types that cannot be a function.
fn is_possibly_function_type(annotation C.TSNode) bool {
	if node_kind(annotation) != 'type_annotation' {
		return false // asserts and type predicates
	}
	mut t := first_named_child(annotation) or { return false }
	for node_kind(t) == 'parenthesized_type' {
		t = first_named_child(t) or { return false }
	}
	match node_kind(t) {
		'conditional_type', 'constructor_type', 'function_type', 'lookup_type', 'infer_type',
		'intersection_type', 'nested_type_identifier', 'this_type', 'index_type_query',
		'readonly_type', 'type_query', 'generic_type', 'type_identifier', 'union_type' {
			return true
		}
		'object_type' {
			for member in named_children(t) {
				if node_kind(member) in ['call_signature', 'construct_signature'] {
					return true
				}
			}
			return false
		}
		else {
			return false
		}
	}
}

// class_like gathers the heritage types (`extends`/`implements`) and the non-static named members
// of a class or interface.
fn (c &Checker) class_like(node C.TSNode) ClassLike {
	mut heritage := []Span{}
	for child in named_children(node) {
		match node_kind(child) {
			'extends_type_clause' {
				for t in named_children(child) {
					heritage << heritage_span(t, node_end(t), syntax_kind_type_reference)
				}
			}
			'class_heritage' {
				for clause in named_children(child) {
					if node_kind(clause) == 'extends_clause' {
						value := node_field(clause, 'value') or { continue }
						end := if args := node_field(clause, 'type_arguments') {
							node_end(args)
						} else {
							node_end(value)
						}
						heritage << heritage_span(value, end, syntax_kind_expression_with_type_arguments)
					} else if node_kind(clause) == 'implements_clause' {
						for t in named_children(clause) {
							heritage << heritage_span(t, node_end(t), syntax_kind_type_reference)
						}
					}
				}
			}
			else {}
		}
	}
	body := node_field(node, 'body') or { return ClassLike{} }
	if heritage.len == 0 {
		return ClassLike{}
	}
	is_interface := node_kind(node) == 'interface_declaration'
	mut members := []Member{}
	for member in named_children(body) {
		if node_kind(member) !in ['method_definition', 'public_field_definition',
			'abstract_method_signature', 'method_signature', 'property_signature'] {
			continue
		}
		name := node_field(member, 'name') or { continue }
		if has_child_kind(member, 'static') {
			continue
		}
		// The constructor of a class has no name in TypeScript; in an interface, `constructor()` is
		// a method with that name.
		if !is_interface && node_kind(member) != 'public_field_definition'
			&& c.pfa_is_constructor(member) {
			continue
		}
		members << Member{
			span: member_span(member)
			name: c.text(name)
		}
	}
	return ClassLike{
		heritage: heritage
		members:  members
	}
}

// heritage_span is the TypeScript node of a heritage type (`X<T>`) that starts at `first`: the
// ExpressionWithTypeArguments of a class's `extends`, and since TypeScript 7.1 a TypeReference in
// `implements` and in an interface's `extends`.
fn heritage_span(first C.TSNode, end int, kind u32) Span {
	return Span{
		key:   ((u64(node_start(first)) << 32) | u64(end)) | heritage_key_bit
		first: first
		end:   end
		kind:  kind
	}
}

// member_span covers what TypeScript considers the member: its decorators (which in tree-sitter
// come before, as siblings) and the `;` or `,` that closes it.
fn member_span(member C.TSNode) Span {
	mut first := member
	for {
		prev := prev_sibling(first) or { break }
		if node_kind(prev) != 'decorator' {
			break
		}
		first = prev
	}
	mut end := node_end(member)
	if node_kind(member) != 'method_definition' {
		if next := next_sibling(member) {
			if node_kind(next) in [';', ','] {
				end = node_end(next)
			}
		}
	}
	return Span{
		key:   node_key(member)
		first: first
		end:   end
	}
}

// inherited_method_findings ports checkClassLikeOrInterfaceNode.
fn (mut c Checker) inherited_method_findings(class_like ClassLike) ![]Finding {
	mut findings := []Finding{}
	for member in class_like.members {
		member_type := c.node_types[member.span.key] or { continue }
		// The member is the node its checks are asked at (`nodeMember`).
		at := c.span_location(member.span.key, member.span.first)
		if member_type.is_null() || !c.returns_thenable_type(member_type, at)! {
			continue
		}
		for span in class_like.heritage {
			heritage := c.node_types[span.key] or { continue }
			if heritage.is_null() {
				continue
			}
			symbol := c.member_if_exists(heritage, member.name)!
			if symbol.is_null()
				|| !c.is_void_returning_function_type(c.symbol_type_at(symbol, at)!, at)! {
				continue
			}
			findings << Finding{
				stmt:       c.position_range(node_start(member.span.first), c.tokens.last_end(member.span.end))
				message_id: 'voidReturnInheritedMethod'
				data:       {
					'heritageTypeName': c.client.type_to_string(c.snapshot, c.project, heritage.id)!
				}
			}
		}
	}
	return findings
}

// member_if_exists ports getMemberIfExists: the member the symbol of the type declares
// (`symbol.members`, which are not instantiated and also hold its type parameters) or, without
// one with that name, the property of the type.
fn (mut c Checker) member_if_exists(t TypeResponse, name string) !SymbolResponse {
	symbol := c.symbol_of(t)!
	if !symbol.is_null() {
		escaped := escape_leading_underscores(name)
		for member in c.symbol_members(symbol.id)! {
			if member.name == escaped {
				return member
			}
		}
	}
	return c.property(t, name)!
}

// returns_thenable ports returnsThenable(checker, node): some signature of the apparent type of
// the node returns a thenable. Without a known type, no.
fn (mut c Checker) returns_thenable(n C.TSNode) !bool {
	t := c.node_type(n) or { return false }
	return c.returns_thenable_type(t, c.symbol_location(n))!
}

fn (mut c Checker) returns_thenable_type(t TypeResponse, at SymbolLocation) !bool {
	for part in c.constituents(c.apparent_of(t)!)! {
		if c.any_signature_is_thenable(part, at)! {
			return true
		}
	}
	return false
}

// any_signature_is_thenable ports anySignatureIsThenableType(checker, node, type): `at` is the
// node.
fn (mut c Checker) any_signature_is_thenable(t TypeResponse, at SymbolLocation) !bool {
	for sig in c.signatures_of(t, signature_kind_call)! {
		if c.is_thenable(c.return_type(sig.id)!, at)! {
			return true
		}
	}
	return false
}

fn (mut c Checker) is_thenable_returning_function_type(t TypeResponse, at SymbolLocation) !bool {
	for part in c.constituents(t)! {
		if c.any_signature_is_thenable(part, at)! {
			return true
		}
	}
	return false
}

// is_void_returning_function_type ports isVoidReturningFunctionType(checker, node, type): some
// signature returns void and none returns a thenable. `at` is the node.
fn (mut c Checker) is_void_returning_function_type(t TypeResponse, at SymbolLocation) !bool {
	mut had_void := false
	for part in c.constituents(t)! {
		for sig in c.signatures_of(part, signature_kind_call)! {
			ret := c.return_type(sig.id)!
			if c.is_thenable(ret, at)! {
				return false
			}
			had_void = had_void || ret.flags & type_flag_void != 0
		}
	}
	return had_void
}

// is_always_thenable ports isAlwaysThenable: every part of the apparent type has a `then` with
// some signature whose first parameter is a function.
fn (mut c Checker) is_always_thenable(n C.TSNode) !bool {
	t := c.node_type(n) or { return false }
	at := c.symbol_location(n)
	for part in c.constituents(c.apparent_of(t)!)! {
		then := c.property(part, 'then')!
		if then.is_null() {
			return false
		}
		mut thenable_signature := false
		for sub in c.constituents(c.symbol_type_at(then, at)!)! {
			for sig in c.signatures_of(sub, signature_kind_call)! {
				params := c.signature_parameters(sig)!
				if params.len != 0 && c.is_function_param(params[0], at)! {
					thenable_signature = true
					break
				}
			}
			if thenable_signature {
				break
			}
		}
		if !thenable_signature {
			return false
		}
	}
	return true
}

// is_function_param ports isFunctionParam(checker, param, node): `at` is the node.
fn (mut c Checker) is_function_param(param ParameterResponse, at SymbolLocation) !bool {
	for part in c.constituents(c.apparent_of(c.parameter_type_at(param, at)!)!)! {
		if c.signatures_of(part, signature_kind_call)!.len != 0 {
			return true
		}
	}
	return false
}

// is_sometimes_thenable ports isSometimesThenable: some part of the apparent type is thenable.
fn (mut c Checker) is_sometimes_thenable(n C.TSNode) !bool {
	t := c.node_type(n) or { return false }
	at := c.symbol_location(n)
	for part in c.constituents(c.apparent_of(t)!)! {
		if c.is_thenable(part, at)! {
			return true
		}
	}
	return false
}
