module rules

import json2
import jsregexp
import time
import tsgo { TypeResponse }
import treesitter { Ident, named_children, node_end, node_field, node_kind, node_start, nodes_of_kinds, position_of }
import offsets { utf16_offsets }

// Port of the `prefer-optional-chain` rule of typescript-eslint 8.62.0 (with
// prefer-optional-chain-utils: gatherLogicalOperands, analyzeChain, compareNodes and
// checkNullishAndReport), with its options, its fix and its suggestions.

const poc_messages = {
	'optionalChainSuggest': 'Change to an optional chain.'
	'preferOptionalChain':  "Prefer using an optional chain expression instead, as it's more concise and easier to read."
}

struct PocOptions {
	allow_unsafe    bool // allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing
	check_any       bool
	check_bigint    bool
	check_boolean   bool
	check_number    bool
	check_string    bool
	check_unknown   bool
	require_nullish bool
}

fn poc_options(options []json2.Any) !PocOptions {
	o := option_object(prefer_optional_chain, options, [
		'allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing',
		'checkAny',
		'checkBigInt',
		'checkBoolean',
		'checkNumber',
		'checkString',
		'checkUnknown',
		'requireNullish',
	])!
	return PocOptions{
		allow_unsafe:    o.bool_value('allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing')!
		check_any:       o.bool_value('checkAny')!
		check_bigint:    o.bool_value('checkBigInt')!
		check_boolean:   o.bool_value('checkBoolean')!
		check_number:    o.bool_value('checkNumber')!
		check_string:    o.bool_value('checkString')!
		check_unknown:   o.bool_value('checkUnknown')!
		require_nullish: o.bool_value('requireNullish')!
	}
}

// PocNode is an ESTree node on the tree-sitter tree: `chain` views a chain root as the
// ChainExpression typescript-estree wraps around it (its `expression` is the same node without
// `chain`). Parentheses are never part of a PocNode.
struct PocNode {
	node  C.TSNode
	chain bool
	empty bool // a missing node (`null` in ESTree)
}

fn poc_view(n C.TSNode) PocNode {
	node := unwrap_parens(n)
	return PocNode{
		node:  node
		chain: is_chain_element(node) && is_estree_chain_root(node)
	}
}

fn poc_view_opt(n ?C.TSNode) PocNode {
	node := n or {
		return PocNode{
			empty: true
		}
	}
	return poc_view(node)
}

fn poc_expression(v PocNode) PocNode {
	return PocNode{
		node: v.node
	}
}

// poc_type is the ESTree type of a view (types and other nodes keep a `ts:` tree-sitter name).
fn poc_type(v PocNode) string {
	if v.chain {
		return 'ChainExpression'
	}
	kind := node_kind(v.node)
	return match kind {
		'identifier', 'undefined', 'property_identifier', 'shorthand_property_identifier' {
			'Identifier'
		}
		'private_property_identifier' {
			'PrivateIdentifier'
		}
		'this' {
			'ThisExpression'
		}
		'super' {
			'Super'
		}
		'string', 'number', 'true', 'false', 'null', 'regex' {
			'Literal'
		}
		'template_string' {
			'TemplateLiteral'
		}
		'member_expression', 'subscript_expression' {
			'MemberExpression'
		}
		'call_expression' {
			args := node_field(v.node, 'arguments') or { return 'CallExpression' }
			function := node_field(v.node, 'function') or { return 'CallExpression' }
			if node_kind(args) == 'template_string' {
				'TaggedTemplateExpression'
			} else if node_kind(function) == 'import' {
				'ImportExpression'
			} else {
				'CallExpression'
			}
		}
		'non_null_expression' {
			'TSNonNullExpression'
		}
		'meta_property' {
			'MetaProperty'
		}
		'binary_expression' {
			estree_binary_kind(v.node)
		}
		'unary_expression' {
			'UnaryExpression'
		}
		'update_expression' {
			'UpdateExpression'
		}
		'await_expression' {
			'AwaitExpression'
		}
		'yield_expression' {
			'YieldExpression'
		}
		'ternary_expression' {
			'ConditionalExpression'
		}
		'sequence_expression' {
			'SequenceExpression'
		}
		'assignment_expression', 'augmented_assignment_expression' {
			'AssignmentExpression'
		}
		'array' {
			'ArrayExpression'
		}
		'object' {
			'ObjectExpression'
		}
		'arrow_function' {
			'ArrowFunctionExpression'
		}
		'function_expression', 'generator_function' {
			'FunctionExpression'
		}
		'class' {
			'ClassExpression'
		}
		'new_expression' {
			'NewExpression'
		}
		'as_expression' {
			'TSAsExpression'
		}
		'satisfies_expression' {
			'TSSatisfiesExpression'
		}
		'type_assertion' {
			'TSTypeAssertion'
		}
		'instantiation_expression' {
			'TSInstantiationExpression'
		}
		'spread_element' {
			'SpreadElement'
		}
		else {
			'ts:${kind}'
		}
	}
}

// NodeComparisonResult of compareNodes.
enum PocCmp {
	equal
	subset
	invalid
}

// poc_compare ports compareNodes: whether `a` is equal to or a subset of `b`.
fn (c &Checker) poc_compare(a PocNode, b PocNode, depth int) PocCmp {
	if a.empty || b.empty {
		return if a.empty && b.empty { PocCmp.equal } else { PocCmp.invalid }
	}
	if depth > max_expression_depth {
		return .invalid
	}
	ta := poc_type(a)
	tb := poc_type(b)
	if ta != tb {
		if ta == 'ChainExpression' && c.poc_chain_look_through(a) {
			return c.poc_compare(poc_expression(a), b, depth + 1)
		}
		if tb == 'ChainExpression' && c.poc_chain_look_through(b) {
			return c.poc_compare(a, poc_expression(b), depth + 1)
		}
		if ta == 'TSNonNullExpression' {
			return c.poc_compare(poc_view(first_named(a.node) or { return .invalid }), b,
				depth + 1)
		}
		if tb == 'TSNonNullExpression' {
			return c.poc_compare(a, poc_view(first_named(b.node) or { return .invalid }),
				depth + 1)
		}
		if ta in ['CallExpression', 'Identifier', 'MemberExpression', 'MetaProperty'] {
			match tb {
				'MemberExpression' {
					property := member_property(b.node) or { return .invalid }
					if node_kind(property) == 'private_property_identifier' {
						return .invalid
					}
					if c.poc_compare(a, poc_member_object(b), depth + 1) != .invalid {
						return .subset
					}
					return .invalid
				}
				'CallExpression' {
					if c.poc_compare(a, poc_callee(b), depth + 1) != .invalid {
						return .subset
					}
					return .invalid
				}
				else {
					return .invalid
				}
			}
		}
		return .invalid
	}
	match ta {
		'ArrayExpression', 'ArrowFunctionExpression', 'ClassExpression', 'FunctionExpression',
		'NewExpression', 'ObjectExpression', 'AssignmentExpression', 'UpdateExpression',
		'YieldExpression' {
			return .invalid
		}
		'CallExpression' {
			if c.poc_compare(a, poc_callee(b), depth + 1) != .invalid {
				return .subset
			}
			if c.poc_compare(poc_callee(a), poc_callee(b), depth + 1) != .equal {
				return .invalid
			}
			if c.poc_compare_list(poc_arguments(a), poc_arguments(b), depth) != .equal {
				return .invalid
			}
			if c.poc_compare(poc_view_opt(node_field(a.node, 'type_arguments')), poc_view_opt(node_field(b.node,
				'type_arguments')), depth + 1) == .equal {
				return .equal
			}
			return .invalid
		}
		'ChainExpression' {
			return c.poc_compare(a, poc_expression(b), depth + 1)
		}
		'Identifier', 'PrivateIdentifier' {
			return if c.poc_name(a.node) == c.poc_name(b.node) {
				PocCmp.equal
			} else {
				PocCmp.invalid
			}
		}
		'Literal' {
			return if c.poc_literal_equal(a.node, b.node) { PocCmp.equal } else { PocCmp.invalid }
		}
		'MemberExpression' {
			property_b := member_property(b.node) or { return .invalid }
			if node_kind(property_b) == 'private_property_identifier' {
				return .invalid
			}
			if c.poc_compare(a, poc_member_object(b), depth + 1) != .invalid {
				return .subset
			}
			if node_kind(a.node) != node_kind(b.node) {
				return .invalid
			}
			if c.poc_compare(poc_member_object(a), poc_member_object(b), depth + 1) != .equal {
				return .invalid
			}
			property_a := member_property(a.node) or { return .invalid }
			return c.poc_compare(poc_view(property_a), poc_view(property_b), depth + 1)
		}
		'TemplateLiteral' {
			raws_a, _ := c.stv_quasis(a.node)
			raws_b, _ := c.stv_quasis(b.node)
			if raws_a.len != raws_b.len {
				return .invalid
			}
			for i, raw in raws_a {
				if cooked_string(raw, true) != cooked_string(raws_b[i], true) {
					return .invalid
				}
			}
			return .equal
		}
		'MetaProperty' {
			return if c.text(a.node) == c.text(b.node) { PocCmp.equal } else { PocCmp.invalid }
		}
		else {
			return c.poc_compare_by_visiting(a, b, ta, depth)
		}
	}
}

// poc_chain_look_through ports isValidChainExpressionToLookThrough: a ChainExpression that is not
// the object of a member access nor a callee (where its parentheses have a meaning).
fn (c &Checker) poc_chain_look_through(v PocNode) bool {
	parent := estree_parent(v.node) or { return true }
	if is_member(parent) {
		object := unwrap_parens(node_field(parent, 'object') or { return true })
		return node_key(object) != node_key(v.node)
	}
	if node_kind(parent) == 'call_expression' {
		callee := unwrap_parens(node_field(parent, 'function') or { return true })
		return node_key(callee) != node_key(v.node)
	}
	return true
}

fn poc_member_object(v PocNode) PocNode {
	return poc_view_opt(node_field(v.node, 'object'))
}

fn poc_callee(v PocNode) PocNode {
	return poc_view_opt(node_field(v.node, 'function'))
}

fn poc_arguments(v PocNode) []PocNode {
	args := call_arguments(v.node) or { return []PocNode{} }
	return args.map(poc_view(it))
}

fn (c &Checker) poc_name(n C.TSNode) string {
	if node_kind(n) == 'private_property_identifier' {
		return c.text(n).trim_left('#')
	}
	return c.identifier_name(n)
}

// poc_literal_equal: the same raw text and the same value (a RegExp value is a different object
// each time, unless V8 rejects both and both are null).
fn (c &Checker) poc_literal_equal(a C.TSNode, b C.TSNode) bool {
	if c.text(a) != c.text(b) {
		return false
	}
	if node_kind(a) == 'regex' {
		pattern := node_field(a, 'pattern') or { return false }
		flags := if f := node_field(a, 'flags') { c.text(f) } else { '' }
		return jsregexp.regexp_new(utf16_units(c.text(pattern)), flags) == none
	}
	return true
}

fn (c &Checker) poc_compare_list(a []PocNode, b []PocNode, depth int) PocCmp {
	if a.len != b.len {
		return .invalid
	}
	for i, x in a {
		if c.poc_compare(x, b[i], depth + 1) != .equal {
			return .invalid
		}
	}
	return .equal
}

// poc_compare_by_visiting ports compareByVisiting: every child in the visitor keys of the type
// is equal. For type nodes and other nodes outside the expressions it compares the tree-sitter
// structure.
fn (c &Checker) poc_compare_by_visiting(a PocNode, b PocNode, typ string, depth int) PocCmp {
	keys := match typ {
		'BinaryExpression', 'LogicalExpression' { ['left', 'right'] }
		'UnaryExpression', 'AwaitExpression', 'SpreadElement' { ['argument'] }
		'ConditionalExpression' { ['condition', 'consequence', 'alternative'] }
		'TSNonNullExpression' { ['expression'] }
		'TSAsExpression', 'TSSatisfiesExpression', 'TSTypeAssertion', 'TSInstantiationExpression',
		'SequenceExpression', 'TaggedTemplateExpression', 'ImportExpression' {
			['children']
		}
		'ThisExpression', 'Super' { []string{} }
		else { ['structure'] }
	}
	for key in keys {
		match key {
			'expression', 'argument' {
				x := first_named(a.node) or { return .invalid }
				y := first_named(b.node) or { return .invalid }
				if c.poc_compare(poc_view(x), poc_view(y), depth + 1) != .equal {
					return .invalid
				}
			}
			'children' {
				// The named children in order: expressions, types and type arguments.
				if c.poc_compare_list(named_children(a.node).map(poc_view(it)), named_children(b.node).map(poc_view(it)),
					depth) != .equal {
					return .invalid
				}
			}
			'structure' {
				if !c.poc_same_structure(a.node, b.node, depth) {
					return .invalid
				}
			}
			else {
				if c.poc_compare(poc_view_opt(node_field(a.node, key)), poc_view_opt(node_field(b.node,
					key)), depth + 1) != .equal {
					return .invalid
				}
			}
		}
	}
	return .equal
}

// poc_same_structure compares two tree-sitter subtrees by kind and leaf text.
fn (c &Checker) poc_same_structure(a C.TSNode, b C.TSNode, depth int) bool {
	if depth > max_expression_depth || node_kind(a) != node_kind(b) {
		return false
	}
	xs := named_children(a)
	ys := named_children(b)
	if xs.len != ys.len {
		return false
	}
	if xs.len == 0 {
		return c.text(a) == c.text(b)
	}
	for i, x in xs {
		if !c.poc_same_structure(x, ys[i], depth + 1) {
			return false
		}
	}
	return true
}

// Operands of gatherLogicalOperands.
enum PocValidity {
	valid
	last
	invalid
}

// NullishComparisonType.
enum PocNullish {
	not_equal_null_or_undefined
	equal_null_or_undefined
	not_strict_equal_null
	strict_equal_null
	not_strict_equal_undefined
	strict_equal_undefined
	not_boolean
	boolean
}

// ComparisonType of the last operand of a chain.
enum PocComparison {
	not_equal
	equal
	not_strict_equal
	strict_equal
}

enum PocYoda {
	yes
	no
	unknown
}

struct PocOperand {
	validity         PocValidity
	node             C.TSNode
	compared_name    PocNode
	nullish          PocNullish
	comparison       PocComparison
	comparison_value PocNode
	yoda             PocYoda
}

// PocLogical is a logical expression visited by the rule and its operands.
struct PocLogical {
	node     C.TSNode
	operator string
	operands []C.TSNode
}

fn (mut c Checker) lint_prefer_optional_chain(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := poc_options(c.rule_options(prefer_optional_chain))!
	mut seen := map[u64]bool{}
	mut logicals := []PocLogical{}
	mut empty_objects := []C.TSNode{} // `(foo || {}).bar`: the `foo`
	mut empty_reports := []C.TSNode{}
	mut empty_logicals := []C.TSNode{}
	mut spans := []Span{}
	for n in c.nodes_of_kinds(root, ['binary_expression'], []string{}) {
		operator := operator_of(n)
		if operator == '&&' || operator == '||' {
			if node_key(n) !in seen {
				operands := poc_flatten(n, operator, mut seen)
				for operand in operands {
					poc_operand_spans(operand, mut spans)
				}
				logicals << PocLogical{
					node:     n
					operator: operator
					operands: operands
				}
			}
		}
		if operator == '||' || operator == '??' {
			if member := poc_empty_object_member(n) {
				left := unwrap_parens(node_field(n, 'left') or { continue })
				empty_objects << left
				empty_reports << member
				empty_logicals << n
				spans << node_span(left)
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for logical in logicals {
		operands := c.poc_gather(logical, o)!
		mut current := []PocOperand{}
		for operand in operands {
			if operand.validity == .invalid {
				c.poc_analyze_chain(logical, current, PocOperand{}, false, o, mut findings)!
				current = []PocOperand{}
			} else if operand.validity == .last {
				c.poc_analyze_chain(logical, current, operand, true, o, mut findings)!
				current = []PocOperand{}
			} else {
				current << operand
			}
		}
		if current.len > 0 {
			c.poc_analyze_chain(logical, current, PocOperand{}, false, o, mut findings)!
		}
	}
	for i, left in empty_objects {
		if c.poc_should_report([left], o)! {
			_, suggestion := c.suggestion('optionalChainSuggest', map[string]string{}, [
				c.poc_empty_object_fix(left, empty_reports[i], empty_logicals[i]),
			])!
			findings << Finding{
				stmt:        position_of(empty_reports[i])
				message_id:  'preferOptionalChain'
				suggestions: [suggestion]
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += logicals.len + empty_objects.len
	return findings
}

// poc_flatten ports flattenLogicalOperands: the operands of a chain of the same operator, in order,
// marking the nested logical expressions as seen.
fn poc_flatten(n C.TSNode, operator string, mut seen map[u64]bool) []C.TSNode {
	seen[node_key(n)] = true
	mut operands := []C.TSNode{}
	mut stack := [node_field(n, 'right') or { return operands }, node_field(n, 'left') or {
		return operands
	}]
	for stack.len > 0 {
		current := unwrap_parens(stack.pop())
		if estree_binary_kind(current) == 'LogicalExpression' && operator_of(current) == operator {
			seen[node_key(current)] = true
			stack << node_field(current, 'right') or { continue }
			stack << node_field(current, 'left') or { continue }
		} else {
			operands << current
		}
	}
	return operands
}

// poc_operand_spans requests the types an operand may need.
fn poc_operand_spans(operand C.TSNode, mut spans []Span) {
	spans << node_span(operand)
	for field in ['left', 'right', 'argument'] {
		if child := node_field(operand, field) {
			inner := unwrap_parens(child)
			spans << node_span(inner)
			if node_kind(inner) == 'unary_expression' {
				if argument := node_field(inner, 'argument') {
					spans << node_span(unwrap_parens(argument))
				}
			}
		}
	}
}

// poc_empty_object_member: the parent of `foo || {}` / `foo ?? {}` when it is a member access
// without `?.`.
fn poc_empty_object_member(n C.TSNode) ?C.TSNode {
	right := unwrap_parens(node_field(n, 'right')?)
	if node_kind(right) != 'object' || named_children(right).len != 0 {
		return none
	}
	parent := estree_parent(n)?
	if !is_member(parent) || is_optional_element(parent) {
		return none
	}
	return parent
}

// ComparisonValueType of gatherLogicalOperands.
enum PocValueType {
	none_
	null_
	undefined_
	undefined_string
}

fn (c &Checker) poc_comparison_value_type(n C.TSNode) PocValueType {
	match node_kind(n) {
		'null' {
			return .null_
		}
		'string' {
			value := c.literal_string_value(n) or { return .none_ }
			return if value == 'undefined' {
				PocValueType.undefined_string
			} else {
				PocValueType.none_
			}
		}
		'identifier', 'undefined' {
			return if c.identifier_name(n) == 'undefined' {
				PocValueType.undefined_
			} else {
				PocValueType.none_
			}
		}
		else {
			return .none_
		}
	}
}

// poc_is_member_based ports isMemberBasedExpression: a MemberExpression or a call of one.
fn poc_is_member_based(v PocNode) bool {
	typ := poc_type(v)
	if typ == 'MemberExpression' {
		return true
	}
	return typ == 'CallExpression' && poc_type(poc_callee(v)) == 'MemberExpression'
}

// poc_gather ports gatherLogicalOperands' classification of the operands.
fn (mut c Checker) poc_gather(logical PocLogical, o PocOptions) ![]PocOperand {
	mut result := []PocOperand{}
	for i, operand in logical.operands {
		more := i < logical.operands.len - 1
		view := poc_view(operand)
		typ := poc_type(view)
		if typ == 'BinaryExpression' {
			result << c.poc_binary_operand(operand, logical.operator)
			continue
		}
		if typ == 'UnaryExpression' {
			argument := node_field(operand, 'argument') or { continue }
			if operator_of(operand) == '!'
				&& (!more || c.poc_valid_false_boolean_check(argument, logical.operator == '||', o)!) {
				result << PocOperand{
					validity:      .valid
					node:          operand
					compared_name: poc_view(argument)
					nullish:       .not_boolean
					yoda:          .no
				}
			} else {
				result << PocOperand{
					validity: .invalid
				}
			}
			continue
		}
		if typ == 'LogicalExpression' {
			result << PocOperand{
				validity: .invalid
			}
			continue
		}
		if !more || c.poc_valid_false_boolean_check(operand, logical.operator == '&&', o)! {
			result << PocOperand{
				validity:      .valid
				node:          operand
				compared_name: view
				nullish:       .boolean
				yoda:          .no
			}
		} else {
			result << PocOperand{
				validity: .invalid
			}
		}
	}
	return result
}

// poc_binary_operand classifies a BinaryExpression operand.
fn (mut c Checker) poc_binary_operand(operand C.TSNode, chain_operator string) PocOperand {
	invalid := PocOperand{
		validity: .invalid
	}
	left := unwrap_parens(node_field(operand, 'left') or { return invalid })
	right := unwrap_parens(node_field(operand, 'right') or { return invalid })
	operator := operator_of(operand)
	mut compared := left
	mut value := c.poc_comparison_value_type(right)
	mut is_yoda := false
	if value == .none_ {
		compared = right
		value = c.poc_comparison_value_type(left)
		is_yoda = true
	}
	yoda_kind := if is_yoda { PocYoda.yes } else { PocYoda.no }
	negated := operator.starts_with('!')
	if value == .undefined_string {
		if node_kind(compared) == 'unary_expression' && operator_of(compared) == 'typeof' {
			argument := unwrap_parens(node_field(compared, 'argument') or { return invalid })
			if node_kind(argument) in ['identifier', 'undefined']
				&& c.poc_is_global_reference(argument) {
				return invalid
			}
			return PocOperand{
				validity:      .valid
				node:          operand
				compared_name: poc_view(argument)
				nullish:       if negated {
					.not_strict_equal_undefined
				} else {
					.strict_equal_undefined
				}
				yoda:          yoda_kind
			}
		}
		return invalid
	}
	if negated != (chain_operator == '||') {
		if operator in ['!=', '=='] && value in [.null_, .undefined_] {
			return PocOperand{
				validity:      .valid
				node:          operand
				compared_name: poc_view(compared)
				nullish:       if negated {
					.not_equal_null_or_undefined
				} else {
					.equal_null_or_undefined
				}
				yoda:          yoda_kind
			}
		}
		if operator in ['!==', '==='] && value == .null_ {
			return PocOperand{
				validity:      .valid
				node:          operand
				compared_name: poc_view(compared)
				nullish:       if negated { .not_strict_equal_null } else { .strict_equal_null }
				yoda:          yoda_kind
			}
		}
		if operator in ['!==', '==='] && value == .undefined_ {
			return PocOperand{
				validity:      .valid
				node:          operand
				compared_name: poc_view(compared)
				nullish:       if negated {
					.not_strict_equal_undefined
				} else {
					.strict_equal_undefined
				}
				yoda:          yoda_kind
			}
		}
	}
	// getBinaryComparisonChain: `x.y == something`.
	left_member := poc_is_member_based(poc_view(left))
	right_member := poc_is_member_based(poc_view(right))
	mut name := left
	mut compared_value := right
	mut chain_yoda := PocYoda.no
	if left_member && !right_member {
	} else if !left_member && right_member {
		name = right
		compared_value = left
		chain_yoda = .yes
	} else if left_member && right_member {
		chain_yoda = .unknown
	} else {
		return invalid
	}
	comparison := match operator {
		'==' { PocComparison.equal }
		'===' { PocComparison.strict_equal }
		'!=' { PocComparison.not_equal }
		'!==' { PocComparison.not_strict_equal }
		else { return invalid }
	}
	return PocOperand{
		validity:         .last
		node:             operand
		compared_name:    poc_view(name)
		comparison:       comparison
		comparison_value: poc_view(compared_value)
		yoda:             chain_yoda
	}
}

// poc_is_global_reference ports isReferenceToGlobalFunction: the first reference with that name
// created in the scope of `n` resolves to no variable, or to one without definitions.
fn (mut c Checker) poc_is_global_reference(n C.TSNode) bool {
	tree := c.stv_scope_tree(n)
	name := c.identifier_name(n)
	for r in tree.scopes[tree.get_scope(n)].references {
		reference := tree.references[r]
		if reference.name == name {
			return reference.resolved < 0 || tree.variables[reference.resolved].defs.len == 0
		}
	}
	return true
}

// poc_parts are the union constituents of a type, each split into its intersection constituents.
fn (mut c Checker) poc_parts(t TypeResponse) ![]TypeResponse {
	mut out := []TypeResponse{}
	for part in c.constituents(t)! {
		out << c.intersection_parts(part)!
	}
	return out
}

// poc_valid_false_boolean_check ports isValidFalseBooleanCheckType.
fn (mut c Checker) poc_valid_false_boolean_check(n C.TSNode, disallow_falsy_literal bool, o PocOptions) !bool {
	t := c.node_type(unwrap_parens(n)) or { return false }
	parts := c.poc_parts(t)!
	if disallow_falsy_literal {
		for part in parts {
			if is_false_literal(part) {
				return false
			}
			value := part.value
			if part.flags & type_flag_string_literal != 0 && value is string && value == '' {
				return false
			}
			if part.flags & type_flag_number_literal != 0 && value is f64 && value == 0 {
				return false
			}
			if part.flags & type_flag_bigint_literal != 0 && value is string && value == '0' {
				return false
			}
		}
	}
	mut allowed := type_flag_null | type_flag_undefined | type_flag_object
	if o.check_any {
		allowed |= type_flag_any
	}
	if o.check_unknown {
		allowed |= type_flag_unknown
	}
	if o.check_string {
		allowed |= type_flag_string_like
	}
	if o.check_number {
		allowed |= type_flag_number_like
	}
	if o.check_boolean {
		allowed |= type_flag_boolean_like
	}
	if o.check_bigint {
		allowed |= type_flag_bigint_like
	}
	for part in parts {
		if part.flags & allowed == 0 {
			return false
		}
	}
	return true
}

// poc_includes_type ports includesType: some union part has the flag, `any` or `unknown`.
fn (mut c Checker) poc_includes_type(v PocNode, flag u32) !bool {
	t := c.node_type(v.node) or { return false }
	for part in c.constituents(t)! {
		if part.flags & (flag | type_flag_any | type_flag_unknown) != 0 {
			return true
		}
	}
	return false
}

// poc_valid_last ports isValidAndLastChainOperand and isValidOrLastChainOperand.
fn (mut c Checker) poc_valid_last(v PocNode, comparison PocComparison, operator string) !bool {
	t := c.node_type(v.node) or { return false }
	parts := c.constituents(t)!
	any_unknown := type_flag_any | type_flag_unknown
	nullish := type_flag_null | type_flag_undefined
	if operator == '&&' {
		return match comparison {
			.equal { !parts.any(it.flags & (any_unknown | nullish) != 0) }
			.strict_equal { !parts.any(it.flags & (any_unknown | type_flag_undefined) != 0) }
			.not_strict_equal { parts.all(it.flags & type_flag_undefined != 0) }
			.not_equal { parts.all(it.flags & nullish != 0) }
		}
	}
	return match comparison {
		.not_equal { !parts.any(it.flags & (any_unknown | nullish) != 0) }
		.not_strict_equal { !parts.any(it.flags & (any_unknown | type_flag_undefined) != 0) }
		.equal { parts.all(it.flags & nullish != 0) }
		.strict_equal { parts.all(it.flags & type_flag_undefined != 0) }
	}
}

// poc_analyze_operand ports analyzeAndChainOperand and analyzeOrChainOperand: the operands that
// make a step of the chain (two for `x !== null && x !== undefined`), or none.
// (An empty list is `null`.)
fn (mut c Checker) poc_analyze_operand(operator string, operand PocOperand, index int, chain []PocOperand) ![]PocOperand {
	has_next := index + 1 < chain.len
	next := if has_next { chain[index + 1] } else { PocOperand{} }
	if operator == '&&' {
		match operand.nullish {
			.boolean, .not_equal_null_or_undefined {
				return [operand]
			}
			.not_strict_equal_null {
				if has_next {
					if next.nullish == .not_strict_equal_undefined
						&& c.poc_compare(operand.compared_name, next.compared_name, 0) == .equal {
						return [operand, next]
					}
					if !c.poc_includes_type(operand.compared_name, type_flag_undefined)! {
						return [operand]
					}
				}
				return []PocOperand{}
			}
			.not_strict_equal_undefined {
				if has_next && next.nullish == .not_strict_equal_null
					&& c.poc_compare(operand.compared_name, next.compared_name, 0) == .equal {
					return [operand, next]
				}
				if c.poc_includes_type(operand.compared_name, type_flag_null)! {
					return []PocOperand{}
				}
				return [operand]
			}
			else {
				return []PocOperand{}
			}
		}
	}
	match operand.nullish {
		.not_boolean, .equal_null_or_undefined {
			return [operand]
		}
		.strict_equal_null {
			if has_next && next.nullish == .strict_equal_undefined
				&& c.poc_compare(operand.compared_name, next.compared_name, 0) == .equal {
				return [operand, next]
			}
			if c.poc_includes_type(operand.compared_name, type_flag_undefined)! {
				return []PocOperand{}
			}
			return [operand]
		}
		.strict_equal_undefined {
			if has_next && next.nullish == .strict_equal_null
				&& c.poc_compare(operand.compared_name, next.compared_name, 0) == .equal {
				return [operand, next]
			}
			if c.poc_includes_type(operand.compared_name, type_flag_null)! {
				return []PocOperand{}
			}
			return [operand]
		}
		else {
			return []PocOperand{}
		}
	}
}

// PocSubChain is the state of analyzeChain: `steps` are its subChain items (a step is one operand
// or the seed of validated operands), `last` the lastChain operand.
struct PocSubChain {
mut:
	steps    [][]PocOperand
	last     PocOperand
	has_last bool
}

fn (s &PocSubChain) flat() []PocOperand {
	mut out := []PocOperand{}
	for step in s.steps {
		out << step
	}
	return out
}

// poc_analyze_chain ports analyzeChain: reports the sub-chains of at least two operands.
fn (mut c Checker) poc_analyze_chain(logical PocLogical, chain []PocOperand, last_chain_operand PocOperand, has_last_chain bool, o PocOptions, mut findings []Finding) ! {
	if chain.len + (if has_last_chain { 1 } else { 0 }) <= 1 {
		return
	}
	mut sub := PocSubChain{}
	mut i := 0
	for i < chain.len {
		flat := sub.flat()
		operand := chain[i]
		validated := c.poc_analyze_operand(logical.operator, operand, i, chain)!
		if validated.len == 0 {
			if flat.len > 0 {
				last_operand := flat.last()
				result := c.poc_compare(last_operand.compared_name, operand.compared_name,
					0)
				if operand.nullish in [.strict_equal_undefined, .not_strict_equal_undefined]
					&& result == .subset {
					sub.last = operand
					sub.has_last = true
				}
			}
			c.poc_report_then_reset(logical, mut sub, []PocOperand{}, o, mut findings)!
			i++
			continue
		}
		i += validated.len - 1
		if flat.len > 0 {
			result := c.poc_compare(flat.last().compared_name, validated.last().compared_name,
				0)
			if result == .subset {
				sub.steps << [validated[0]]
			} else if result == .invalid {
				c.poc_report_then_reset(logical, mut sub, validated, o, mut findings)!
			}
		} else {
			sub.steps << [validated[0]]
		}
		i++
	}
	flat := sub.flat()
	if flat.len > 0 {
		if has_last_chain {
			last := last_chain_operand
			resolved := c.poc_resolve_operand_subset(flat.last(), last)
			if resolved.is_subset
				&& c.poc_valid_last(resolved.comparison_value, last.comparison, logical.operator)! {
				sub.last = PocOperand{
					...last
					compared_name:    resolved.compared_name
					comparison_value: resolved.comparison_value
					yoda:             if resolved.is_yoda { PocYoda.yes } else { PocYoda.no }
				}
				sub.has_last = true
			}
		}
	}
	c.poc_report_then_reset(logical, mut sub, []PocOperand{}, o, mut findings)!
}

// poc_report_then_reset ports maybeReportThenReset.
fn (mut c Checker) poc_report_then_reset(logical PocLogical, mut sub PocSubChain, seed []PocOperand, o PocOptions, mut findings []Finding) ! {
	if sub.steps.len + (if sub.has_last { 1 } else { 0 }) > 1 {
		flat := sub.flat()
		mut nodes := flat.map(it.node)
		if !sub.has_last && nodes.len > 0 {
			nodes = nodes[..nodes.len - 1].clone()
		}
		if c.poc_should_report(nodes, o)! {
			mut chain := flat.clone()
			if sub.has_last {
				chain << sub.last
			}
			findings << c.poc_report(logical, chain, sub.has_last, o)!
		}
	}
	sub.steps = if seed.len > 0 { [seed] } else { [][]PocOperand{} }
	sub.last = PocOperand{}
	sub.has_last = false
}

// poc_should_report ports checkNullishAndReport: with requireNullish, some node may be nullish.
fn (mut c Checker) poc_should_report(nodes []C.TSNode, o PocOptions) !bool {
	if !o.require_nullish {
		return true
	}
	for n in nodes {
		t := c.node_type(n) or { continue }
		for part in c.constituents(t)! {
			if part.flags & (type_flag_null | type_flag_undefined) != 0 {
				return true
			}
		}
	}
	return false
}

// PocResolved is the result of resolveOperandSubset.
struct PocResolved {
	compared_name    PocNode
	comparison_value PocNode
	is_subset        bool
	is_yoda          bool
}

fn (c &Checker) poc_resolve_operand_subset(previous PocOperand, last PocOperand) PocResolved {
	name_subset := c.poc_compare(previous.compared_name, last.compared_name, 0) == .subset
	if last.yoda != .unknown {
		return PocResolved{
			compared_name:    last.compared_name
			comparison_value: last.comparison_value
			is_subset:        name_subset
			is_yoda:          last.yoda == .yes
		}
	}
	value_subset := c.poc_compare(previous.compared_name, last.comparison_value, 0) == .subset
	if name_subset && !value_subset {
		return PocResolved{
			compared_name:    last.compared_name
			comparison_value: last.comparison_value
			is_subset:        true
		}
	}
	if !name_subset && value_subset {
		return PocResolved{
			compared_name:    last.comparison_value
			comparison_value: last.compared_name
			is_subset:        true
			is_yoda:          true
		}
	}
	return PocResolved{
		compared_name:    last.comparison_value
		comparison_value: last.comparison_value
		is_subset:        false
		is_yoda:          true
	}
}

// poc_report_start ports the start of getReportRange: the first token of the first operand,
// extended over the `(` tokens just before it inside the logical expression.
fn (c &Checker) poc_report_start(first C.TSNode, boundary C.TSNode) int {
	mut start := node_start(first)
	limit := node_start(boundary)
	for start > limit {
		end := c.tokens.last_end(start)
		if end == 0 || c.src[end - 1] != `(` || end - 1 < limit {
			break
		}
		start = end - 1
	}
	return start
}

// poc_report_end ports the end of getReportRange: the last token of the last operand, extended
// over the `)` tokens just after it inside the logical expression.
fn (mut c Checker) poc_report_end(last C.TSNode, boundary C.TSNode) int {
	tokens := c.source_tokens(last)
	mut end := node_end(last)
	limit := node_end(boundary)
	for end < limit {
		token := tokens.after(end, false) or { break }
		if !c.token_is(token, ')') || token.end > limit {
			break
		}
		end = token.end
	}
	return end
}

// PocPart is a part of a flattened chain (flattenChainExpression): the base expression, a member
// access or the arguments of a call.
struct PocPart {
mut:
	optional     bool
	non_null     bool
	requires_dot bool
	precedence   int
	text         string
}

// poc_flatten_chain ports flattenChainExpression.
fn (mut c Checker) poc_flatten_chain(v PocNode, depth int) []PocPart {
	if v.empty || depth > max_expression_depth {
		return []PocPart{}
	}
	if v.chain {
		return c.poc_flatten_chain(poc_expression(v), depth + 1)
	}
	match poc_type(v) {
		'CallExpression' {
			// The arguments, from the first `(` after the type arguments (or the callee) to the end
			// of the call, after the text of the type arguments.
			mut text := ''
			mut after := unwrap_parens(node_field(v.node, 'function') or { return []PocPart{} })
			if type_arguments := node_field(v.node, 'type_arguments') {
				text = c.text(type_arguments)
				after = type_arguments
			}
			open := c.source_token_after(after, '(') or { return []PocPart{} }
			mut parts := c.poc_flatten_chain(poc_callee(v), depth + 1)
			parts << PocPart{
				optional:   is_optional_element(v.node)
				precedence: precedence_invalid
				text:       text + c.src[open.start..node_end(v.node)]
			}
			return parts
		}
		'MemberExpression' {
			computed := node_kind(v.node) == 'subscript_expression'
			property := member_property(v.node) or { return []PocPart{} }
			object := poc_member_object(v)
			mut parts := c.poc_flatten_chain(object, depth + 1)
			parts << PocPart{
				non_null:     poc_type(object) == 'TSNonNullExpression'
				optional:     is_optional_element(v.node)
				// A computed property is already wrapped in [], so it needs no parentheses.
				precedence:   if computed {
					precedence_invalid
				} else {
					estree_operator_precedence(property)
				}
				requires_dot: !computed
				text:         if computed { '[${c.text(property)}]' } else { c.text(property) }
			}
			return parts
		}
		'TSNonNullExpression' {
			return c.poc_flatten_chain(poc_view_opt(first_named(v.node)), depth + 1)
		}
		else {
			return [
				PocPart{
					precedence: estree_operator_precedence(v.node)
					text:       c.text(v.node)
				},
			]
		}
	}
}

// poc_report ports getReportDescriptor: the finding of a chain (with its last operand, if
// `has_last`), with its fix or, when the fix could change the type of the expression, the same
// fix as a suggestion.
fn (mut c Checker) poc_report(logical PocLogical, chain []PocOperand, has_last bool, o PocOptions) !Finding {
	last := chain.last()
	// An optional chain adds `undefined` to the type: without an operand that already includes it
	// (or a last operand that is an equality check) the fix is only suggested.
	mut use_suggestion := false
	if !o.allow_unsafe && !has_last
		&& last.nullish !in [.equal_null_or_undefined, .not_equal_null_or_undefined,
			.strict_equal_undefined, .not_strict_equal_undefined]
		&& !(logical.operator == '||' && last.nullish == .not_boolean) {
		use_suggestion = true
		for operand in chain {
			if c.poc_includes_type(poc_view(operand.node), type_flag_undefined)! {
				use_suggestion = false
				break
			}
		}
	}
	// The minimum number of `?.`: each operand adds what it has beyond the previous ones, and the
	// first part it adds becomes optional.
	mut parts := []PocPart{}
	for current in chain {
		next := c.poc_flatten_chain(current.compared_name, 0)
		if next.len > parts.len {
			mut diff := next[parts.len..].clone()
			if parts.len > 0 {
				diff[0].optional = true
			}
			parts << diff
		}
	}
	mut new_code := ''
	for part in parts {
		if part.optional {
			new_code += '?.'
		} else {
			if part.non_null {
				new_code += '!'
			}
			if part.requires_dot {
				new_code += '.'
			}
		}
		new_code += if part.precedence != precedence_invalid && part.precedence < precedence_member {
			'(${part.text})'
		} else {
			part.text
		}
	}
	if poc_type(poc_view(last.node)) == 'BinaryExpression' {
		// Retain the ending comparison: `x && x.a != null`, `x && typeof x.a !== 'undefined'`.
		left := unwrap_parens(node_field(last.node, 'left') or { return error('no left operand') })
		right := unwrap_parens(node_field(last.node, 'right') or {
			return error('no right operand')
		})
		operator := operator_of(last.node)
		new_code = if last.yoda == .yes {
			'${c.text(left)} ${operator} ${poc_unary_prefix(right)}${new_code}'
		} else {
			'${poc_unary_prefix(left)}${new_code} ${operator} ${c.text(right)}'
		}
	} else if last.nullish == .not_boolean {
		new_code = '!${new_code}'
	}
	start := c.poc_report_start(chain[0].node, logical.node)
	end := c.poc_report_end(last.node, logical.node)
	fix := c.poc_fix(logical.node, start, end, new_code)
	finding := Finding{
		stmt:       c.position_range(start, end)
		message_id: 'preferOptionalChain'
	}
	if use_suggestion {
		_, suggestion := c.suggestion('optionalChainSuggest', map[string]string{}, [fix])!
		return Finding{
			...finding
			suggestions: [suggestion]
		}
	}
	return Finding{
		...finding
		has_fix: true
		fix:     fix
	}
}

// poc_unary_prefix: the operator of a UnaryExpression operand and a space (`typeof `), which the
// new code keeps.
fn poc_unary_prefix(n C.TSNode) string {
	return if node_kind(n) == 'unary_expression' { '${operator_of(n)} ' } else { '' }
}

// poc_fix ports the fixer of getReportDescriptor: the report range becomes the new code. When the
// range has a `(` that closes after it, the whole logical expression is replaced instead, by the
// new code and what follows the range without the `)` tokens left unmatched. Like the original,
// that second form reads the text of the expression with offsets of the file, so it is only
// right for an expression at the start of the file.
fn (mut c Checker) poc_fix(node C.TSNode, start int, end int, new_code string) Fix {
	tokens := c.source_tokens(node).inside(node_start(node), node_end(node), false)
	mut unclosed := 0
	for token in tokens {
		if token.start >= start && token.end <= end {
			if c.token_is(token, '(') {
				unclosed++
			} else if c.token_is(token, ')') {
				unclosed--
			}
		}
	}
	if unclosed <= 0 || end >= node_end(node) {
		return fix_replace_range(start, end, new_code)
	}
	mut open_outside := 0
	mut unmatched := []int{}
	for token in tokens {
		if token.end <= end {
			continue
		}
		if c.token_is(token, '(') {
			open_outside++
		} else if c.token_is(token, ')') {
			if open_outside > 0 {
				open_outside--
			} else {
				unmatched << token.start
			}
		}
	}
	mut byte_offsets := [end]
	byte_offsets << unmatched
	indexes := utf16_offsets(c.src, byte_offsets)
	mut units := utf16_units(c.text(node))
	for k := indexes.len - 1; k >= 1; k-- {
		if indexes[k] < units.len {
			units.delete(indexes[k])
		}
	}
	rest := if indexes[0] < units.len { units[indexes[0]..] } else { []u16{} }
	return fix_replace(node, new_code + stv_units_string(rest))
}

// poc_empty_object_fix ports the fixer of the `(foo || {}).bar` suggestion: `foo?.bar`, with
// `foo` in parentheses when it binds looser than a call.
fn (c &Checker) poc_empty_object_fix(left C.TSNode, member C.TSNode, logical C.TSNode) Fix {
	mut left_text := c.text(left)
	if ts_operator_precedence(left, operator_of(logical), false) < precedence_left_hand_side {
		left_text = '(${left_text})'
	}
	mut property_text := ''
	if property := member_property(member) {
		property_text = c.text(property)
	}
	if node_kind(member) == 'subscript_expression' {
		property_text = '[${property_text}]'
	}
	return fix_replace(member, '${left_text}?.${property_text}')
}

// poc_ident_at is the position of a byte offset, like sourceCode.getLocFromIndex: the printed line
// and column come from the offset (see position_at).
fn (c &Checker) poc_ident_at(offset int) Ident {
	return c.position_at(offset)
}
