module rules

import estree
import json2
import treesitter { Ident }
import tsgo { TypeResponse }

// Port of the `svelte/@typescript-eslint/no-unnecessary-condition` rule of eslint-plugin-svelte
// 3.24.1 (src/rules/@typescript-eslint/no-unnecessary-condition.ts): an older version of
// typescript-eslint's rule (veslint's no_unnecessary_condition.v ports 8.72.2's, whose checks
// differ) that leaves alone the conditions of the template and of `$:` statements that use a
// `let` or `var` of the component's top level, with its helpers of src/utils/ts-utils. It has no
// `conditions`: like upstream it also runs on the other files ESLint lints with the plugin.
//
// It reads the ESTree ESLint traverses (SvscEs: the document's for a .svelte file) and asks tsgo
// the types of its nodes through their twins of the lint code (SvscBridge). The types a check
// needs depend on other types, so the checks run again until every type they asked for is known
// (each run asks for the missing ones in one batch).

const svnuc_messages = {
	'alwaysTruthy':               'Unnecessary conditional, value is always truthy.'
	'alwaysFalsy':                'Unnecessary conditional, value is always falsy.'
	'alwaysTruthyFunc':           'This callback should return a conditional, but return is always truthy.'
	'alwaysFalsyFunc':            'This callback should return a conditional, but return is always falsy.'
	'neverNullish':               'Unnecessary conditional, expected left-hand side of `??` operator to be possibly null or undefined.'
	'alwaysNullish':              'Unnecessary conditional, left-hand side of `??` operator is always `null` or `undefined`.'
	'literalBooleanExpression':   'Unnecessary conditional, both sides of the expression are literal values.'
	'noOverlapBooleanExpression': 'Unnecessary conditional, the types have no overlap.'
	'never':                      'Unnecessary conditional, value is `never`.'
	'neverOptionalChain':         'Unnecessary optional chain on a non-nullish value.'
	'noStrictNullCheck':          'This rule requires the `strictNullChecks` compiler option to be turned on to function correctly.'
}

const svnuc_array_predicates = ['filter', 'find', 'some', 'every']

struct SvnucOptions {
	allow_constant_loop_conditions   bool
	allow_without_strict_null_checks bool
}

fn svnuc_options(options []json2.Any) !SvnucOptions {
	o := option_object(svelte_ts_no_unnecessary_condition, options, [
		'allowConstantLoopConditions',
		'allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing',
	])!
	return SvnucOptions{
		allow_constant_loop_conditions:   o.bool_value('allowConstantLoopConditions')!
		allow_without_strict_null_checks: o.bool_value('allowRuleToRunWithoutStrictNullChecksIKnowWhatIAmDoing')!
	}
}

// Svnuc is the state of one run of the checks.
struct Svnuc {
mut:
	e SvscEs
	b SvscBridge
	o SvnucOptions
	// types: the constrained type of each node asked for (a null type: none); need: the nodes
	// asked for during this run whose types are not known yet.
	types map[int]TypeResponse
	need  map[int]bool
	// mutable: the ranges of the references to the top-level `let` and `var` variables
	// (mutableVarReferenceIds); scripts: the ranges of the <script> elements.
	mutable  [][]int
	scripts  [][]int
	reactive bool
	findings []Finding
}

fn (mut c Checker) lint_svelte_ts_no_unnecessary_condition(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	o := svnuc_options(c.rule_options(svelte_ts_no_unnecessary_condition))!
	if !c.scope_setup.type_information {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	b := c.svsc_bridge(root, &e, abs_path) or { return [] }
	mut s := Svnuc{
		e: e
		b: b
		o: o
	}
	if c.is_svelte() {
		c.svnuc_scope(mut s)
	}
	mut passes := 0
	for {
		s.findings = []
		s.reactive = false
		c.svnuc_walk(mut s)!
		passes++
		if s.need.len == 0 || passes > 8 {
			break
		}
		c.svnuc_resolve(mut s, abs_path, mut stats)!
	}
	mut findings := []Finding{}
	if !c.strict_null_checks && !o.allow_without_strict_null_checks {
		// ESLint reports it at line 0, column 0.
		findings << Finding{
			stmt:       Ident{
				row: -1
			}
			message_id: 'noStrictNullCheck'
		}
	}
	findings << s.findings
	stats.checked++
	return findings
}

// svnuc_scope collects the references to the mutable variables of the global and module scopes
// and the ranges of the scripts.
fn (c &Checker) svnuc_scope(mut s Svnuc) {
	doc := c.svelte.doc
	info := &doc.scope
	if info.scopes.len == 0 {
		return
	}
	mut scopes := [0]
	module_scope := c.svsc_toplevel_scope()
	if module_scope != 0 {
		scopes << module_scope
	}
	es := &doc.es
	for scope in scopes {
		for v in info.scopes[scope].variables {
			variable := info.variables[v]
			mut mutable := false
			for def in variable.defs {
				kind, declarator := c.svsc_def(def)
				if kind != .variable || declarator < 0 {
					continue
				}
				declaration := es.nodes[declarator].parent
				if declaration >= 0 && es.typ(declaration) == .variable_declaration
					&& (es.string_of(declaration, .kind) or { '' }) in ['var', 'let'] {
					mutable = true
					break
				}
			}
			if !mutable {
				continue
			}
			for r in variable.references {
				id := info.references[r].identifier
				if id >= 0 {
					s.mutable << [es.nodes[id].start, es.nodes[id].end]
				}
			}
		}
	}
	for ch in doc.nodes[0].children {
		n := doc.nodes[ch]
		if n.typ == .script_element {
			s.scripts << [n.start, n.end]
		}
	}
}

// svnuc_resolve asks tsgo the types of the nodes of `need`.
fn (mut c Checker) svnuc_resolve(mut s Svnuc, abs_path string, mut stats Stats) ! {
	mut nodes := []C.vt_node{}
	mut indexes := []int{}
	for i, _ in s.need {
		if i in s.types {
			continue
		}
		lint := s.b.lint_of(i) or {
			s.types[i] = TypeResponse{}
			continue
		}
		ts := s.b.lint.ts_node(lint) or {
			s.types[i] = TypeResponse{}
			continue
		}
		nodes << ts
		indexes << i
	}
	s.need = map[int]bool{}
	if nodes.len == 0 {
		return
	}
	c.resolve_node_types(nodes, abs_path, mut stats)!
	for k, i in indexes {
		t := c.node_type(nodes[k]) or {
			s.types[i] = TypeResponse{}
			continue
		}
		s.types[i] = c.constrained(t)!
	}
}

// svnuc_type is getNodeType: the constrained type of a node, none when unknown (or not asked
// for yet: it is then asked for in the next run).
fn (mut s Svnuc) svnuc_type(i int) ?TypeResponse {
	if i < 0 {
		return none
	}
	if t := s.types[i] {
		if t.is_null() {
			return none
		}
		return t
	}
	s.need[i] = true
	return none
}

fn (s &Svnuc) svnuc_typ(c &Checker, i int) string {
	return s.e.type_name(c, i)
}

fn (s &Svnuc) nd(i int, key estree.Key) int {
	return s.e.t.node(i, key) or { -1 }
}

// svnuc_walk runs the listeners in the order of ESLint's traversal.
fn (mut c Checker) svnuc_walk(mut s Svnuc) ! {
	t := s.e.t
	for step in s.e.steps {
		i := step.node
		typ := s.svnuc_typ(c, i)
		if step.leave {
			if typ == 'SvelteReactiveStatement' {
				s.reactive = false
			}
			continue
		}
		match typ {
			'SvelteReactiveStatement' {
				s.reactive = true
			}
			'BinaryExpression' {
				c.svnuc_binary(mut s, i)!
			}
			'CallExpression' {
				c.svnuc_call(mut s, i)!
				if t.flag(i, .optional) or { false } {
					c.svnuc_optional_chain(mut s, i, s.nd(i, .callee), '')!
				}
			}
			'ConditionalExpression', 'IfStatement' {
				c.svnuc_check(mut s, s.nd(i, .test), false)!
			}
			'DoWhileStatement', 'ForStatement', 'WhileStatement' {
				c.svnuc_loop(mut s, i)!
			}
			'LogicalExpression' {
				if (t.string_of(i, .operator) or { '' }) == '??' {
					c.svnuc_check_nullish(mut s, s.nd(i, .left))!
				} else {
					c.svnuc_check(mut s, s.nd(i, .left), false)!
				}
			}
			'MemberExpression' {
				if t.flag(i, .optional) or { false } {
					computed := t.flag(i, .computed) or { false }
					c.svnuc_optional_chain(mut s, i, s.nd(i, .object), if computed {
						''
					} else {
						'.'
					})!
				}
			}
			else {}
		}
	}
}

// svnuc_report reports a node.
fn (c &Checker) svnuc_report(mut s Svnuc, i int, message_id string) {
	s.findings << c.svsc_report(&s.e, i, message_id, {})
}

// svnuc_reactive_var is hasSvelteReactiveVar: the node is in a `$:` statement or in the
// template (outside every script, when there is one) and uses a mutable top-level variable.
fn (s &Svnuc) svnuc_reactive_var(i int) bool {
	n := s.e.t.nodes[i]
	in_scope := s.reactive || (s.scripts.len > 0 && s.scripts.all(n.end <= it[0] || it[1] <= n.start))
	if !in_scope {
		return false
	}
	return s.mutable.any(n.start <= it[0] && it[1] <= n.end)
}

// svnuc_parts are unionTypeParts.
fn (mut c Checker) svnuc_parts(t TypeResponse) ![]TypeResponse {
	if t.flags & type_flag_union != 0 {
		mut out := []TypeResponse{}
		for m in c.members_of(t)! {
			out << c.svnuc_parts(m)!
		}
		return out
	}
	return [t]
}

// svnuc_is_literal is TS's type.isLiteral(): a string, number or BigInt literal type.
fn svnuc_is_literal(t TypeResponse) bool {
	return t.flags & type_flag_literal_value != 0
}

// svnuc_literal_truthy is `Boolean(type.value)`: a BigInt literal's value is an object, truthy.
fn svnuc_literal_truthy(t TypeResponse) bool {
	if t.flags & type_flag_bigint_literal != 0 {
		return true
	}
	return literal_truthy(t)
}

// svnuc_truthy_literal is isTruthyLiteral of ts-utils.
fn (mut c Checker) svnuc_truthy_literal(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for m in c.members_of(t)! {
			if !c.svnuc_truthy_literal(m)! {
				return false
			}
		}
		return true
	}
	return is_true_literal(t) || (svnuc_is_literal(t) && svnuc_literal_truthy(t))
}

// svnuc_falsy is isFalsyType of ts-utils.
fn (mut c Checker) svnuc_falsy(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for m in c.members_of(t)! {
			if !c.svnuc_falsy(m)! {
				return false
			}
		}
		return true
	}
	if t.flags & (type_flag_undefined | type_flag_null | type_flag_void) != 0 {
		return true
	}
	if svnuc_is_literal(t) {
		return !svnuc_literal_truthy(t)
	}
	return is_false_literal(t)
}

// svnuc_possibly_falsy is the rule's isPossiblyFalsy.
fn (mut c Checker) svnuc_possibly_falsy(t TypeResponse) !bool {
	for part in c.svnuc_parts(t)! {
		if c.svnuc_truthy_literal(part)! {
			continue
		}
		if part.flags & type_flag_possibly_falsy != 0 {
			return true
		}
	}
	return false
}

// svnuc_possibly_truthy is the rule's isPossiblyTruthy.
fn (mut c Checker) svnuc_possibly_truthy(t TypeResponse) !bool {
	for part in c.svnuc_parts(t)! {
		if !c.svnuc_falsy(part)! {
			return true
		}
	}
	return false
}

// svnuc_nullable is isNullableType of ts-utils.
fn (mut c Checker) svnuc_nullable(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for m in c.members_of(t)! {
			if c.svnuc_nullable(m)! {
				return true
			}
		}
		return false
	}
	return t.flags & (type_flag_null | type_flag_undefined) != 0
}

// svnuc_nullish is isNullishType of ts-utils.
fn (mut c Checker) svnuc_nullish(t TypeResponse) !bool {
	if t.flags & type_flag_union != 0 {
		for m in c.members_of(t)! {
			if !c.svnuc_nullish(m)! {
				return false
			}
		}
		return true
	}
	return t.flags & (type_flag_null | type_flag_undefined) != 0
}

// svnuc_array is nodeIsArrayType; svnuc_tuple is nodeIsTupleType.
fn (mut c Checker) svnuc_array(mut s Svnuc, i int) !bool {
	t := s.svnuc_type(i) or { return false }
	return c.is_array(t)!
}

fn (mut c Checker) svnuc_tuple(mut s Svnuc, i int) bool {
	t := s.svnuc_type(i) or { return false }
	return t.is_tuple_type
}

// svnuc_array_index is isArrayIndexExpression.
fn (mut c Checker) svnuc_array_index(mut s Svnuc, i int) !bool {
	t := s.e.t
	if i < 0 || s.svnuc_typ(c, i) != 'MemberExpression' || !(t.flag(i, .computed) or { false }) {
		return false
	}
	object := s.nd(i, .object)
	if c.svnuc_array(mut s, object)! {
		return true
	}
	property := s.nd(i, .property)
	return c.svnuc_tuple(mut s, object) && property >= 0 && s.svnuc_typ(c, property) != 'Literal'
}

// svnuc_check is checkNode.
fn (mut c Checker) svnuc_check(mut s Svnuc, i int, unary_not bool) ! {
	if i < 0 || s.svnuc_reactive_var(i) {
		return
	}
	t := s.e.t
	typ := s.svnuc_typ(c, i)
	if typ == 'UnaryExpression' && (t.string_of(i, .operator) or { '' }) == '!' {
		return c.svnuc_check(mut s, s.nd(i, .argument), true)
	}
	if c.svnuc_array_index(mut s, i)! {
		return
	}
	if typ == 'LogicalExpression' && (t.string_of(i, .operator) or { '' }) != '??' {
		return c.svnuc_check(mut s, s.nd(i, .right), false)
	}
	ty := s.svnuc_type(i) or { return }
	parts := c.svnuc_parts(ty)!
	if parts.any(it.flags & (type_flag_any | type_flag_unknown | type_flag_type_parameter) != 0) {
		return
	}
	message_id := if parts.any(it.flags & type_flag_never != 0) {
		'never'
	} else if !c.svnuc_possibly_truthy(ty)! {
		if unary_not { 'alwaysTruthy' } else { 'alwaysFalsy' }
	} else if !c.svnuc_possibly_falsy(ty)! {
		if unary_not { 'alwaysFalsy' } else { 'alwaysTruthy' }
	} else {
		''
	}
	if message_id != '' {
		c.svnuc_report(mut s, i, message_id)
	}
}

// svnuc_check_nullish is checkNodeForNullish: the left side of `??`.
fn (mut c Checker) svnuc_check_nullish(mut s Svnuc, i int) ! {
	if i < 0 || s.svnuc_reactive_var(i) {
		return
	}
	ty := s.svnuc_type(i) or { return }
	if ty.flags & (type_flag_any | type_flag_unknown) != 0 {
		return
	}
	parts := c.svnuc_parts(ty)!
	mut message_id := ''
	if parts.any(it.flags & type_flag_never != 0) {
		message_id = 'never'
	} else if !c.svnuc_nullable(ty)! {
		mut skip := c.svnuc_array_index(mut s, i)!
		if !skip && s.svnuc_typ(c, i) == 'ChainExpression' {
			expression := s.nd(i, .expression)
			if expression >= 0 && s.svnuc_typ(c, expression) != 'TSNonNullExpression' {
				skip = c.svnuc_chain_array_index(mut s, expression)!
			}
		}
		if !skip {
			message_id = 'neverNullish'
		}
	} else if c.svnuc_nullish(ty)! {
		message_id = 'alwaysNullish'
	}
	if message_id != '' {
		c.svnuc_report(mut s, i, message_id)
	}
}

// svnuc_binary is checkIfBinaryExpressionIsNecessaryConditional.
fn (mut c Checker) svnuc_binary(mut s Svnuc, i int) ! {
	if s.svnuc_reactive_var(i) {
		return
	}
	operator := s.e.t.string_of(i, .operator) or { '' }
	if operator !in nuco_bool_operators {
		return
	}
	left := s.svnuc_type(s.nd(i, .left))
	right := s.svnuc_type(s.nd(i, .right))
	left_type := left or { return }
	right_type := right or { return }
	if c.svnuc_literal(left_type)! && c.svnuc_literal(right_type)! {
		c.svnuc_report(mut s, i, 'literalBooleanExpression')
		return
	}
	// Workaround for https://github.com/microsoft/TypeScript/issues/37160.
	if !c.strict_null_checks {
		return
	}
	loose := operator in ['==', '!=']
	if (left_type.flags == type_flag_undefined
		&& !c.svnuc_comparable(right_type, type_flag_undefined, loose)!)
		|| (right_type.flags == type_flag_undefined
			&& !c.svnuc_comparable(left_type, type_flag_undefined, loose)!)
		|| (left_type.flags == type_flag_null && !c.svnuc_comparable(right_type, type_flag_null, loose)!)
		|| (right_type.flags == type_flag_null && !c.svnuc_comparable(left_type, type_flag_null, loose)!) {
		c.svnuc_report(mut s, i, 'noOverlapBooleanExpression')
	}
}

// svnuc_literal is the rule's isLiteral.
fn (mut c Checker) svnuc_literal(t TypeResponse) !bool {
	return t.flags & type_flag_boolean_literal != 0 || c.svnuc_nullish(t)! || svnuc_is_literal(t)
}

fn (mut c Checker) svnuc_comparable(t TypeResponse, flag u32, loose bool) !bool {
	mut flags := flag | type_flag_any | type_flag_unknown | type_flag_type_parameter
	if loose {
		flags |= type_flag_null | type_flag_undefined
	}
	for part in c.svnuc_parts(t)! {
		if part.flags & flags != 0 {
			return true
		}
	}
	return false
}

// svnuc_loop is checkIfLoopIsNecessaryConditional.
fn (mut c Checker) svnuc_loop(mut s Svnuc, i int) ! {
	test := s.nd(i, .test)
	if test < 0 {
		return
	}
	if s.o.allow_constant_loop_conditions {
		if ty := s.svnuc_type(test) {
			if ty.flags & type_flag_boolean_literal != 0 && c.type_string(ty)! == 'true' {
				return
			}
		}
	}
	c.svnuc_check(mut s, test, false)!
}

// svnuc_call is checkCallExpression: the callbacks of filter, find, some and every on arrays.
fn (mut c Checker) svnuc_call(mut s Svnuc, i int) ! {
	t := s.e.t
	callee := s.nd(i, .callee)
	if callee < 0 || s.svnuc_typ(c, callee) != 'MemberExpression' {
		return
	}
	property := s.nd(callee, .property)
	if property < 0 || s.svnuc_typ(c, property) != 'Identifier'
		|| (t.string_of(property, .name) or { '' }) !in svnuc_array_predicates {
		return
	}
	object := s.nd(callee, .object)
	if !c.svnuc_array(mut s, object)! && !c.svnuc_tuple(mut s, object) {
		return
	}
	arguments := t.list(i, .arguments) or { return }
	if arguments.len == 0 {
		return
	}
	callback := arguments[0]
	callback_type := s.svnuc_typ(c, callback)
	if callback_type in ['ArrowFunctionExpression', 'FunctionExpression'] {
		body := s.nd(callback, .body)
		if body >= 0 {
			if s.svnuc_typ(c, body) != 'BlockStatement' {
				return c.svnuc_check(mut s, body, false)
			}
			statements := t.list(body, .body) or { []int{} }
			if statements.len == 1 && s.svnuc_typ(c, statements[0]) == 'ReturnStatement' {
				argument := s.nd(statements[0], .argument)
				if argument >= 0 {
					return c.svnuc_check(mut s, argument, false)
				}
			}
		}
	}
	ty := s.svnuc_type(callback) or { return }
	signatures := c.call_signatures_of(ty)!
	if signatures.len == 0 {
		return
	}
	mut returns := []TypeResponse{}
	for sig in signatures {
		returns << c.return_type(sig.id)!
	}
	if returns.any(it.flags & (type_flag_any | type_flag_unknown) != 0) {
		return
	}
	mut falsy := false
	mut truthy := false
	for r in returns {
		if c.svnuc_possibly_falsy(r)! {
			falsy = true
		}
		if c.svnuc_possibly_truthy(r)! {
			truthy = true
		}
	}
	if !falsy {
		c.svnuc_report(mut s, callback, 'alwaysTruthyFunc')
	} else if !truthy {
		c.svnuc_report(mut s, callback, 'alwaysFalsyFunc')
	}
}

// svnuc_chain_array_index is optionChainContainsOptionArrayIndex.
fn (mut c Checker) svnuc_chain_array_index(mut s Svnuc, i int) !bool {
	mut node := i
	for depth := 0; depth < max_expression_depth; depth++ {
		typ := s.svnuc_typ(c, node)
		lhs := if typ == 'CallExpression' { s.nd(node, .callee) } else { s.nd(node, .object) }
		if lhs < 0 {
			return false
		}
		if (s.e.t.flag(node, .optional) or { false }) && c.svnuc_array_index(mut s, lhs)! {
			return true
		}
		if s.svnuc_typ(c, lhs) !in ['MemberExpression', 'CallExpression'] {
			return false
		}
		node = lhs
	}
	return false
}

// svnuc_property_type is getTypeOfPropertyOfType (a null type: undefined).
fn (mut c Checker) svnuc_property_type(t TypeResponse, name string) !TypeResponse {
	prop := c.property(t, name)!
	if prop.is_null() {
		return TypeResponse{}
	}
	return c.symbol_type(prop.id)!
}

// svnuc_nullable_property is isNullablePropertyType.
fn (mut c Checker) svnuc_nullable_property(object TypeResponse, property TypeResponse, depth int) !bool {
	if property.flags & type_flag_union != 0 {
		if depth > max_type_depth {
			return false
		}
		for part in c.members_of(property)! {
			if c.svnuc_nullable_property(object, part, depth + 1)! {
				return true
			}
		}
		return false
	}
	if property.flags & (type_flag_number_literal | type_flag_string_literal) != 0 {
		pt := c.svnuc_property_type(object, literal_type_name(property))!
		if !pt.is_null() {
			return c.svnuc_nullable(pt)!
		}
	}
	name := c.type_name(property, 0)!
	if name != 'string' && name != 'number' {
		return false
	}
	key_flag := if name == 'string' { type_flag_string } else { type_flag_number }
	for info in c.index_infos(object.id)! {
		if info.key_type.flags == key_flag {
			return true
		}
	}
	return false
}

// svnuc_nullable_origin_from_prev is isNullableOriginFromPrev.
fn (mut c Checker) svnuc_nullable_origin_from_prev(mut s Svnuc, i int) !bool {
	t := s.e.t
	previous := s.svnuc_type(s.nd(i, .object)) or { return false }
	property := s.nd(i, .property)
	if previous.flags & type_flag_union == 0 || property < 0
		|| s.svnuc_typ(c, property) != 'Identifier' {
		return false
	}
	computed := t.flag(i, .computed) or { false }
	mut own_nullable := false
	for part in c.members_of(previous)! {
		if computed {
			pt := s.svnuc_type(property) or { continue }
			if c.svnuc_nullable_property(part, pt, 0)! {
				own_nullable = true
				break
			}
			continue
		}
		name := t.string_of(property, .name) or { '' }
		pt := c.svnuc_property_type(part, name)!
		if !pt.is_null() && c.svnuc_nullable(pt)! {
			own_nullable = true
			break
		}
	}
	return !own_nullable && c.svnuc_nullable(previous)!
}

// svnuc_optionable is isOptionableExpression.
fn (mut c Checker) svnuc_optionable(mut s Svnuc, i int) !bool {
	ty := s.svnuc_type(i) or { return false }
	own_nullable := if s.svnuc_typ(c, i) == 'MemberExpression' {
		!c.svnuc_nullable_origin_from_prev(mut s, i)!
	} else {
		true
	}
	return ty.flags & (type_flag_any | type_flag_unknown) != 0
		|| (c.svnuc_nullable(ty)! && own_nullable)
}

// svnuc_optional_chain is checkOptionalChain: an unnecessary `?.`, fixed to `fix`.
fn (mut c Checker) svnuc_optional_chain(mut s Svnuc, i int, before int, fix string) ! {
	if c.svnuc_chain_array_index(mut s, i)! {
		return
	}
	to_check := before
	if to_check < 0 || s.svnuc_reactive_var(to_check) {
		return
	}
	if c.svnuc_optionable(mut s, to_check)! {
		return
	}
	start, end := c.svnuc_question_dot(&s, i, before) or { return }
	s.findings << Finding{
		...c.sv_report(start, end, 'neverOptionalChain', {})
		has_fix: true
		fix:     Fix{
			start: start
			end:   end
			text:  fix
		}
	}
}

// svnuc_question_dot is the `?.` token after the object or the callee of the node (its range).
fn (c &Checker) svnuc_question_dot(s &Svnuc, i int, before int) ?(int, int) {
	from := s.e.t.nodes[before].end
	if s.e.svelte {
		tok := c.sv_token_after_value(from, '?.')?
		return tok.start, tok.end
	}
	ts := s.e.t.ts_node(i)?
	kind := if s.svnuc_typ(c, i) == 'CallExpression' { '?.' } else { 'optional_chain' }
	for child in children_of_kind(ts, kind) {
		if treesitter.node_start(child) >= from {
			return treesitter.node_start(child), treesitter.node_end(child)
		}
	}
	return none
}
