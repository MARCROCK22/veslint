module rules

import estree
import json2
import math
import time

// Port of the `unicorn/no-useless-undefined` rule of eslint-plugin-unicorn 79.0.0, with its
// options, fixes and suggestions. Its check of call arguments (`checkArguments`) only runs for files
// that are not TypeScript (`isTypeScriptFile(context.physicalFilename)` ends the rule before it):
// of the files veslint lints, the .vue files.

const unuu_messages = {
	'no-useless-undefined':            'Do not use useless `undefined`.'
	'no-useless-undefined/suggestion': 'Use the indexed access directly.'
}

// unuu_options gives checkArguments and checkArrowFunctionBody.
fn unuu_options(options []json2.Any) !(bool, bool) {
	o := option_object(unicorn_no_useless_undefined, options, ['checkArguments',
		'checkArrowFunctionBody'])!
	return o.bool_value('checkArguments')!, o.bool_value('checkArrowFunctionBody')!
}

// unuu_compare_function_names are compareFunctionNames, and unuu_methods_with_undefined_argument
// methodsWithUndefinedArgument: a trailing `undefined` is not the same as no argument for them.
const unuu_compare_function_names = ['is', 'equal', 'notEqual', 'strictEqual', 'notStrictEqual',
	'propertyVal', 'notPropertyVal', 'not', 'include', 'property', 'toBe', 'toHaveBeenCalledWith',
	'toContain', 'toContainEqual', 'toEqual', 'same', 'notSame', 'strictSame', 'strictNotSame']
const unuu_methods_with_undefined_argument = ['push', 'unshift', 'includes', 'concat', 'splice',
	'toSpliced', 'lastIndexOf', 'reduce', 'reduceRight', 'String', 'fromCharCode', 'fromCodePoint',
	'Number', 'max', 'min', 'hypot', 'Array', 'of', 'from', 'structuredClone', 'add', 'has', 'delete',
	'set', 'createContext', 'useRef', 'ref']

// unuu_should_ignore ports shouldIgnore: the callee's name (an identifier, or the property of a
// non-computed member) is one of those, or `set` followed by a capital letter (`setState`).
fn unuu_should_ignore(t &estree.EsTree, callee int) bool {
	name := match t.typ(callee) {
		.identifier {
			t.string_of(callee, .name) or { '' }
		}
		.member_expression {
			property := t.node(callee, .property) or { return false }
			if (t.flag(callee, .computed) or { false }) || t.typ(property) != .identifier {
				''
			} else {
				t.string_of(property, .name) or { '' }
			}
		}
		else {
			''
		}
	}
	return name in unuu_compare_function_names || name in unuu_methods_with_undefined_argument
		|| (name.len > 3 && name.starts_with('set') && name[3] >= `A` && name[3] <= `Z`)
}

// unuu_call ports the CallExpression listener of checkArguments: a trailing `undefined` argument.
fn (mut c Checker) unuu_call(t &estree.EsTree, tokens &SourceTokens, node int) ![]Finding {
	arguments := t.list(node, .arguments) or { return [] }
	if arguments.len == 0 {
		return []
	}
	last := arguments.last()
	callee := t.node(node, .callee) or { return [] }
	if !un_is_undefined(t, last) || unuu_should_ignore(t, callee) {
		return []
	}
	// Function#bind(): only its `this` argument.
	if !(t.flag(node, .optional) or { false }) && t.typ(callee) == .member_expression
		&& !(t.flag(callee, .computed) or { false }) && arguments.len != 1 {
		property := t.node(callee, .property) or { return [] }
		if t.typ(property) == .identifier && (t.string_of(property, .name) or { '' }) == 'bind' {
			return []
		}
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, last)
		message_id: 'no-useless-undefined'
	}
	removal := c.unb_argument_removal_range(t, tokens, last) or { return [finding] }
	if un_has_comment_in_range(tokens, removal.start, removal.end) {
		return [finding]
	}
	fix := c.unb_remove_argument(t, tokens, last) or { return [finding] }
	return [c.with_fixes(finding, [fix])!]
}

// UnuuIndex is the result of getIndexAccess: the index without a positive constant subtracted from
// it, and that constant.
struct UnuuIndex {
	node   int
	offset f64
}

// UnuuAccess is the result of getIndexedAccess: the member expression (without TypeScript wrappers)
// and its index.
struct UnuuAccess {
	node  int
	index UnuuIndex
}

// UnuuBound is an entry of lowerBoundComparison or upperBoundComparison.
struct UnuuBound {
	valid  bool
	addend f64
	kind   string
}

fn unuu_lower_bound(side string, operator string) ?UnuuBound {
	if side == 'left' {
		return match operator {
			'>=' { UnuuBound{true, 0, ''} }
			'>' { UnuuBound{true, -1, ''} }
			'<' { UnuuBound{false, 0, ''} }
			'<=' { UnuuBound{false, -1, ''} }
			else { none }
		}
	}
	return match operator {
		'<=' { UnuuBound{true, 0, ''} }
		'<' { UnuuBound{true, -1, ''} }
		'>' { UnuuBound{false, 0, ''} }
		'>=' { UnuuBound{false, -1, ''} }
		else { none }
	}
}

fn unuu_upper_bound(side string, operator string) ?UnuuBound {
	if side == 'left' {
		return match operator {
			'<' { UnuuBound{true, 0, 'length'} }
			'<=' { UnuuBound{true, 0, 'lengthMinusOne'} }
			'>=' { UnuuBound{false, 0, 'length'} }
			'>' { UnuuBound{false, 0, 'lengthMinusOne'} }
			else { none }
		}
	}
	return match operator {
		'>' { UnuuBound{true, 0, 'length'} }
		'>=' { UnuuBound{true, 0, 'lengthMinusOne'} }
		'<=' { UnuuBound{false, 0, 'length'} }
		'<' { UnuuBound{false, 0, 'lengthMinusOne'} }
		else { none }
	}
}

// unuu_is_safe_integer is Number.isSafeInteger.
fn unuu_is_safe_integer(value ?f64) bool {
	v := value or { return false }
	return !math.is_nan(v) && !math.is_inf(v, 0) && math.floor(v) == v
		&& math.abs(v) <= 9007199254740991.0
}

fn (mut c Checker) lint_unicorn_no_useless_undefined(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	check_arguments, check_arrow_function_body := unuu_options(c.rule_options(unicorn_no_useless_undefined))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	calls := check_arguments && !c.is_typescript_file()
	for node in 0 .. t.nodes.len {
		f := match t.typ(node) {
			.identifier { c.unuu_identifier(t, tokens, node, check_arrow_function_body)! }
			.conditional_expression { c.unuu_conditional(t, tokens, node)! }
			.call_expression {
				if calls { c.unuu_call(t, tokens, node)! } else { continue }
			}
			else { continue }
		}
		stats.checked++
		findings << f
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unuu_function ports getFunction(sourceCode.getScope(node)): the block of the closest function
// scope around the node, that is the closest function around it (a `return`, a `yield` and the
// body of an arrow function are never directly in a class field or a static block).
fn unuu_function(t &estree.EsTree, node int) int {
	for n := t.nodes[node].parent; n >= 0; n = t.nodes[n].parent {
		if t.typ(n) in [.function_declaration, .function_expression, .arrow_function_expression] {
			return n
		}
	}
	return -1
}

// unuu_return_type_kind is functionNode.returnType?.typeAnnotation?.type; none without one.
fn unuu_return_type(t &estree.EsTree, function int) ?estree.NodeType {
	if function < 0 {
		return none
	}
	return_type := t.node(function, .return_type)?
	return t.typ(t.node(return_type, .type_annotation)?)
}

fn (mut c Checker) unuu_identifier(t &estree.EsTree, tokens &SourceTokens, node int, check_arrow_function_body bool) ![]Finding {
	if !un_is_undefined(t, node) {
		return []
	}
	parent := t.nodes[node].parent
	if parent < 0 {
		return []
	}
	finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: 'no-useless-undefined'
	}
	match t.typ(parent) {
		.return_statement {
			// `return undefined`
			if t.node(parent, .argument) or { -1 } != node {
				return []
			}
			function := unuu_function(t, node)
			if function >= 0 && t.node(function, .return_type) != none {
				typ := unuu_return_type(t, function) or { estree.NodeType.program }
				if typ !in [.ts_undefined_keyword, .ts_void_keyword] {
					return []
				}
			}
			return [c.with_fixes(finding, c.un_replace_node_and_spaces_before(t, tokens, node,
				''))!]
		}
		.yield_expression {
			// `yield undefined`
			if t.flag(parent, .delegate) or { false } || t.node(parent, .argument) or { -1 } != node {
				return []
			}
			return [c.with_fixes(finding, c.un_replace_node_and_spaces_before(t, tokens, node,
				''))!]
		}
		.arrow_function_expression {
			// `() => undefined`
			if !check_arrow_function_body || t.node(parent, .body) or { -1 } != node {
				return []
			}
			function := unuu_function(t, node)
			if function >= 0 && t.node(function, .return_type) != none {
				return []
			}
			return [c.with_fixes(finding, c.un_replace_node_and_spaces_before(t, tokens, node,
				' {}'))!]
		}
		.variable_declarator {
			// `let foo = undefined`; a `var` initializer can reset an existing binding.
			if t.node(parent, .init) or { -1 } != node {
				return []
			}
			declaration := t.nodes[parent].parent
			if declaration < 0 || (t.string_of(declaration, .kind) or { '' }) != 'let' {
				return []
			}
			id := t.node(parent, .id) or { return [] }
			if t.typ(id) != .identifier {
				return []
			}
			start := t.nodes[id].end
			_, end := c.un_parenthesized_range(t, tokens, node)
			// A comment in the removed range would go: no fix.
			if un_has_comment_in_range(tokens, start, end) {
				return [finding]
			}
			return [c.with_fixes(finding, [fix_remove_range(start, end)])!]
		}
		.assignment_pattern {
			// `const {foo = undefined} = {}`
			if t.node(parent, .right) or { -1 } != node {
				return []
			}
			left := t.node(parent, .left) or { return [] }
			start := t.nodes[left].end
			_, end := c.un_parenthesized_range(t, tokens, node)
			if un_has_comment_in_range(tokens, start, end) {
				return [finding]
			}
			mut fixes := [fix_remove_range(start, end)]
			grand := t.nodes[parent].parent
			if (t.node(left, .type_annotation) != none || c.is_typescript_file())
				&& !(t.flag(left, .optional) or { false }) && unb_is_function(t, grand)
				&& parent in (t.list(grand, .params) or { []int{} }) {
				if annotation := t.node(left, .type_annotation) {
					fixes << fix_insert_at(t.nodes[annotation].start, '?')
				} else {
					fixes << fix_insert_at(t.nodes[left].end, '?')
				}
			}
			return [c.with_fixes(finding, fixes)!]
		}
		else {
			return []
		}
	}
}

// unuu_contains_optional_chain ports containsOptionalChain of utils/comparison.js: a `?.` anywhere
// in the node.
fn unuu_contains_optional_chain(t &estree.EsTree, node int) bool {
	if t.typ(node) == .chain_expression {
		return true
	}
	if t.typ(node) in [.call_expression, .member_expression] && (t.flag(node, .optional) or { false }) {
		return true
	}
	return t.children(node).any(unuu_contains_optional_chain(t, it))
}

// unuu_index_access ports getIndexAccess.
fn unuu_index_access(t &estree.EsTree, from int) UnuuIndex {
	node := un_unwrap_ts_expression(t, from)
	if t.typ(node) == .binary_expression && (t.string_of(node, .operator) or { '' }) == '-' {
		right := t.node(node, .right) or { -1 }
		offset := if right >= 0 { un_static_number_value(t, right) } else { none }
		if unuu_is_safe_integer(offset) {
			value := offset or { 0 }
			if value > 0 {
				return UnuuIndex{
					node:   t.node(node, .left) or { node }
					offset: value
				}
			}
		}
	}
	return UnuuIndex{
		node:   node
		offset: 0
	}
}

// unuu_indexed_access ports getIndexedAccess.
fn unuu_indexed_access(t &estree.EsTree, from int) ?UnuuAccess {
	node := un_unwrap_ts_expression(t, from)
	if !un_is_member(t, node, computed: true, optional: false)
		|| unuu_contains_optional_chain(t, node) {
		return none
	}
	object := t.node(node, .object)?
	property := t.node(node, .property)?
	if unb_has_side_effect(t, object, true) || unb_has_side_effect(t, property, true) {
		return none
	}
	return UnuuAccess{
		node:  node
		index: unuu_index_access(t, property)
	}
}

// unuu_offset_validity ports getOffsetComparisonValidity.
fn unuu_offset_validity(comparison ?UnuuBound, boundary f64, offset f64) ?bool {
	bound := comparison?
	if boundary == offset + bound.addend {
		return bound.valid
	}
	return none
}

// unuu_lower_bound_validity ports getLowerBoundTestValidity.
fn (mut c Checker) unuu_lower_bound_validity(t &estree.EsTree, test int, index UnuuIndex) ?bool {
	operator := t.string_of(test, .operator) or { '' }
	left := t.node(test, .left)?
	right := t.node(test, .right)?
	left_number := un_static_number_value(t, left)
	right_number := un_static_number_value(t, right)
	if unuu_is_safe_integer(right_number) && c.un_is_same_reference(t, left, index.node) {
		return unuu_offset_validity(unuu_lower_bound('left', operator), right_number or { 0 },
			index.offset)
	}
	if unuu_is_safe_integer(left_number) && c.un_is_same_reference(t, right, index.node) {
		return unuu_offset_validity(unuu_lower_bound('right', operator), left_number or { 0 },
			index.offset)
	}
	return none
}

// unuu_length_bound_kind ports getLengthBoundKind.
fn (mut c Checker) unuu_length_bound_kind(t &estree.EsTree, node int, object int) string {
	if c.un_is_length_of(t, node, object) {
		return 'length'
	}
	if c.un_is_length_minus_one_of(t, node, object) {
		return 'lengthMinusOne'
	}
	return ''
}

// unuu_kind_validity ports getBoundKindComparisonValidity.
fn unuu_kind_validity(comparison ?UnuuBound, kind string) ?bool {
	bound := comparison?
	if bound.kind == kind {
		return bound.valid
	}
	return none
}

// unuu_upper_bound_validity ports getUpperBoundTestValidity.
fn (mut c Checker) unuu_upper_bound_validity(t &estree.EsTree, test int, access UnuuAccess) ?bool {
	if access.index.offset != 0 {
		return none
	}
	operator := t.string_of(test, .operator) or { '' }
	left := t.node(test, .left)?
	right := t.node(test, .right)?
	object := t.node(access.node, .object)?
	right_kind := c.unuu_length_bound_kind(t, right, object)
	if right_kind != '' && c.un_is_same_reference(t, left, access.index.node) {
		return unuu_kind_validity(unuu_upper_bound('left', operator), right_kind)
	}
	left_kind := c.unuu_length_bound_kind(t, left, object)
	if left_kind != '' && c.un_is_same_reference(t, right, access.index.node) {
		return unuu_kind_validity(unuu_upper_bound('right', operator), left_kind)
	}
	return none
}

// unuu_test_validity ports getIndexedAccessTestValidity.
fn (mut c Checker) unuu_test_validity(t &estree.EsTree, from int, access UnuuAccess) ?bool {
	test := un_unwrap_ts_expression(t, from)
	if t.typ(test) != .binary_expression
		|| (t.string_of(test, .operator) or { '' }) !in ['<', '<=', '>', '>=']
		|| unuu_contains_optional_chain(t, test) {
		return none
	}
	if valid := c.unuu_lower_bound_validity(t, test, access.index) {
		return valid
	}
	return c.unuu_upper_bound_validity(t, test, access)
}

// unuu_is_reference_context ports isReferenceContext: the outermost TypeScript wrapper of the node
// is a callee, a tag or the argument of `delete`.
fn unuu_is_reference_context(t &estree.EsTree, node int) bool {
	expression := un_outermost_ts_expression(t, node)
	parent := t.nodes[expression].parent
	if parent < 0 {
		return false
	}
	return match t.typ(parent) {
		.call_expression { t.node(parent, .callee) or { -1 } == expression }
		.tagged_template_expression { t.node(parent, .tag) or { -1 } == expression }
		.unary_expression { (t.string_of(parent, .operator) or { '' }) == 'delete' }
		else { false }
	}
}

fn (mut c Checker) unuu_conditional(t &estree.EsTree, tokens &SourceTokens, node int) ![]Finding {
	consequent := t.node(node, .consequent) or { return [] }
	alternate := t.node(node, .alternate) or { return [] }
	test := t.node(node, .test) or { return [] }
	is_consequent_undefined := un_is_undefined(t, consequent)
	if is_consequent_undefined == un_is_undefined(t, alternate) {
		return []
	}
	indexed_access_node := if is_consequent_undefined { alternate } else { consequent }
	access := unuu_indexed_access(t, indexed_access_node) or { return [] }
	is_access_when_test_passes := !is_consequent_undefined
	validity := c.unuu_test_validity(t, test, access) or { return [] }
	if validity != is_access_when_test_passes {
		return []
	}
	reported := if is_consequent_undefined { consequent } else { alternate }
	mut finding := Finding{
		stmt:       c.es_tree_position(t, reported)
		message_id: 'no-useless-undefined'
	}
	if unuu_is_reference_context(t, node)
		|| tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len > 0 {
		return [finding]
	}
	// The text of the branch keeps a type assertion (`array[index] as string`).
	replacement := c.un_text(t, indexed_access_node)
	semicolon := if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false),
		replacement)
	{
		';'
	} else {
		''
	}
	mut fixes := [fix_replace_range(t.nodes[node].start, t.nodes[node].end, semicolon + replacement)]
	fixes << c.unb_fix_space_around_keyword(t, tokens, node)
	ok, suggestion := c.suggestion('no-useless-undefined/suggestion', {}, fixes)!
	if ok {
		finding = Finding{
			...finding
			suggestions: [suggestion]
		}
	}
	return [finding]
}
