module rules

import estree
import math
import time
import x.json2

// Port of the `unicorn/no-array-callback-reference` rule of eslint-plugin-unicorn 79.0.0, with its
// option `ignore` and its suggestions.

const unacr_messages = {
	'error-with-name':      'Do not pass function `{{name}}` directly to `.{{method}}(…)`.'
	'error-without-name':   'Do not pass function directly to `.{{method}}(…)`.'
	'replace-with-name':    'Replace function `{{name}}` with `… => {{name}}({{parameters}})`.'
	'replace-without-name': 'Replace function with `… => …({{parameters}})`.'
}

const unacr_default_ignored_callees = ['Promise', 'React.Children', 'Children', 'lodash', 'underscore', '_',
	'Async', 'async', 'this', '$', 'jQuery']

struct UnacrMethod {
	parameters        []string = ['element', 'index', 'array']
	min_parameters    int      = 1
	returns_undefined bool
	ignore            []string
	ignored_object    string // shouldIgnoreCallExpression: the object of the callee is this identifier
}

fn unacr_method(name string) ?UnacrMethod {
	return match name {
		'every', 'find', 'findLast', 'findIndex', 'findLastIndex', 'some' {
			UnacrMethod{
				ignore: ['Boolean']
			}
		}
		'filter' {
			UnacrMethod{
				ignore:         ['Boolean']
				ignored_object: 'Vue'
			}
		}
		'flatMap' {
			UnacrMethod{}
		}
		'forEach' {
			UnacrMethod{
				returns_undefined: true
			}
		}
		'map' {
			UnacrMethod{
				ignore:         ['String', 'Number', 'BigInt', 'Boolean', 'Symbol']
				ignored_object: 'types'
			}
		}
		'reduce', 'reduceRight' {
			UnacrMethod{
				parameters:     ['accumulator', 'element', 'index', 'array']
				min_parameters: 2
			}
		}
		else {
			none
		}
	}
}

// unacr_options reads `ignore`: the callees to ignore after the default ones.
fn unacr_options(options []json2.Any) ![]string {
	o := option_object(unicorn_no_array_callback_reference, options, ['ignore'])!
	mut ignored := unacr_default_ignored_callees.clone()
	ignored << o.string_list('ignore')!
	return ignored
}

fn unacr_should_ignore_call(t &estree.EsTree, call int, method string, o UnacrMethod, ignored_callees []string) bool {
	parent := t.nodes[call].parent
	if method !in ['reduce', 'reduceRight'] && parent >= 0 && t.typ(parent) == .await_expression
		&& t.node(parent, .argument) or { -1 } == call {
		return true
	}
	object := t.node(t.node(call, .callee) or { return false }, .object) or { return false }
	if un_is_node_matches(t, object, ignored_callees) {
		return true
	}
	if t.typ(object) == .call_expression
		&& un_is_node_matches(t, t.node(object, .callee) or { -1 }, ignored_callees) {
		return true
	}
	return o.ignored_object != '' && t.typ(object) == .identifier
		&& (t.string_of(object, .name) or { '' }) == o.ignored_object
}

// unacr_receiver_type_options are receiverTypeOptions over those of isKnownNonIndexedCollection.
fn unacr_receiver_type_options() UnbTypeOptions {
	return UnbTypeOptions{
		...unb_indexed_collection_options()
		allow_nullish_in_mixed_union:    true
		check_class_heritage:            true
		check_class_syntax:              true
		treat_mixed_union_as_non_target: true
	}
}

// unacr_is_definitely_not_function_value ports isDefinitelyNotFunctionValue: a value that cannot
// be a function, also through `const` variables.
fn (mut c Checker) unacr_is_definitely_not_function_value(root C.vt_node, t &estree.EsTree, node int, mut visited map[int]bool) bool {
	n := unb_unwrap_ts(t, node)
	if t.typ(n) in [.array_expression, .binary_expression, .class_expression, .literal,
		.object_expression, .template_literal, .unary_expression, .update_expression]
		|| un_is_undefined(t, n) {
		return true
	}
	_, initializer := c.unb_const_definition(root, t, n) or { return false }
	if visited[initializer] {
		return false
	}
	visited[initializer] = true
	return c.unacr_is_definitely_not_function_value(root, t, initializer, mut visited)
}

// unacr_referenced_names ports getReferencedNames: the names of the reference identifiers in the
// node (by the visitor keys).
fn unacr_referenced_names(t &estree.EsTree, node int, mut names map[string]bool) {
	if t.typ(node) == .identifier && unb_is_reference_identifier(t, node) {
		names[t.string_of(node, .name) or { '' }] = true
	}
	for child in t.children(node) {
		unacr_referenced_names(t, child, mut names)
	}
}

// unacr_suggestion_parameters ports getSuggestionParameters.
fn unacr_suggestion_parameters(t &estree.EsTree, call int, callback int, parameters []string) []string {
	mut referenced := map[string]bool{}
	unacr_referenced_names(t, callback, mut referenced)
	mut suggestion_parameters := parameters.clone()
	object := t.node(t.node(call, .callee) or { -1 }, .object) or { -1 }
	if t.typ(callback) == .identifier && object >= 0 && t.typ(object) == .identifier {
		object_name := t.string_of(object, .name) or { '' }
		if element_name := unb_singular(object_name) {
			if element_name != '' {
				suggestion_parameters = parameters.map(fn [parameters, referenced, element_name, object_name] (parameter string) string {
					replacement := match parameter {
						'element' { element_name }
						'array' { object_name }
						else { '' }
					}
					return if replacement != '' && replacement !in parameters
						&& !referenced[replacement] && unb_identifier_regex_test(replacement) {
						replacement
					} else {
						parameter
					}
				})
			}
		}
	}
	return suggestion_parameters.map(fn [referenced] (parameter string) string {
		mut out := parameter
		for referenced[out] {
			out += '_'
		}
		return out
	})
}

// unacr_declaration ports getDeclaration: the function a callback refers to, or -1.
fn (mut c Checker) unacr_declaration(root C.vt_node, t &estree.EsTree, callback int) int {
	if t.typ(callback) == .identifier {
		v := c.unb_find_variable(root, t, callback)
		if v < 0 {
			return -1
		}
		tree := c.scope_tree(root)
		if tree.variables[v].defs.len == 0 {
			return -1
		}
		definition := tree.variables[v].defs[0]
		if definition.kind == .function_name {
			return c.es_index_of(t, definition.node) or { -1 }
		}
		if definition.kind == .variable {
			return c.es_index_of(t, definition.init or { return -1 }) or { -1 }
		}
		return -1
	}
	if t.typ(callback) != .member_expression || (t.flag(callback, .computed) or { false }) {
		return -1
	}
	property := t.node(callback, .property) or { return -1 }
	if t.typ(property) != .identifier {
		return -1
	}
	// `object.method`, where `object` is bound to an object literal in the same scope
	_, initializer := c.unb_const_definition(root, t, unb_unwrap_ts(t, t.node(callback, .object) or {
		return -1
	})) or { return -1 }
	object_expression := unb_unwrap_ts(t, initializer)
	if t.typ(object_expression) != .object_expression {
		return -1
	}
	name := t.string_of(property, .name) or { return -1 }
	for p in t.list(object_expression, .properties) or { return -1 } {
		if t.typ(p) != .property || (t.flag(p, .computed) or { false }) {
			continue
		}
		key := t.node(p, .key) or { continue }
		if t.typ(key) == .identifier && (t.string_of(key, .name) or { '' }) == name {
			return t.node(p, .value) or { -1 }
		}
	}
	return -1
}

// unacr_declared_parameter_count ports getDeclaredParameterCount: none when the callback does not
// refer to a function; a rest parameter takes any number of arguments (max_int).
fn (mut c Checker) unacr_declared_parameter_count(root C.vt_node, t &estree.EsTree, callback int) ?int {
	declaration := c.unacr_declaration(root, t, callback)
	if !unb_is_function(t, declaration) {
		return none
	}
	params := t.list(declaration, .params) or { []int{} }
	if params.len > 0 && t.typ(params.last()) == .rest_element {
		return max_int
	}
	return params.len
}

// unacr_ternary_branches ports getTernaryConsequentAndALternate.
fn unacr_ternary_branches(t &estree.EsTree, node int, mut out []int) {
	if t.typ(node) == .conditional_expression {
		unacr_ternary_branches(t, t.node(node, .consequent) or { return }, mut out)
		unacr_ternary_branches(t, t.node(node, .alternate) or { return }, mut out)
		return
	}
	out << node
}

// unacr_predicate_return ports hasTypePredicateReturnType.
fn unacr_predicate_return(t &estree.EsTree, node int) bool {
	annotation := t.node(node, .return_type) or { return false }
	inner := t.node(annotation, .type_annotation) or { return false }
	return t.typ(inner) == .ts_type_predicate
}

// unacr_predicate_function_type ports hasTypePredicateFunctionType.
fn unacr_predicate_function_type(t &estree.EsTree, node int) bool {
	annotation := t.node(node, .type_annotation) or { return false }
	function_type := t.node(annotation, .type_annotation) or { return false }
	return unacr_predicate_return(t, function_type)
}

// unacr_type_predicate_callback ports isTypePredicateCallback.
fn (mut c Checker) unacr_type_predicate_callback(root C.vt_node, t &estree.EsTree, callback int) bool {
	if t.typ(callback) != .identifier {
		return false
	}
	ts := t.ts_node(callback) or { return false }
	tree := c.scope_tree(root)
	v := tree.find_variable(tree.get_scope(ts), t.string_of(callback, .name) or { '' }, t.nodes[callback].start)
	if v < 0 || tree.variables[v].defs.len == 0 {
		return false
	}
	def := tree.variables[v].defs[0]
	match def.kind {
		.function_name {
			return unacr_predicate_return(t, c.es_index_of(t, def.node) or { return false })
		}
		.import_binding {
			return true
		}
		.parameter {
			return unacr_predicate_function_type(t, c.es_index_of(t, def.name) or { return false })
		}
		.variable {
			if id := def.decl_id {
				if unacr_predicate_function_type(t, c.es_index_of(t, id) or { -1 }) {
					return true
				}
			}
			init := c.es_index_of(t, def.init or { return false }) or { return false }
			return t.typ(init) in [.arrow_function_expression, .function_expression]
				&& unacr_predicate_return(t, init)
		}
		else {
			return false
		}
	}
}

fn (mut c Checker) lint_unicorn_no_array_callback_reference(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	ignored_callees := unacr_options(c.rule_options(unicorn_no_array_callback_reference))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := &UnbTypeContext{
		root:     root
		abs_path: abs_path
		stats:    unsafe { &stats }
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if !un_is_method_call(t, node,
			minimum_arguments: 1
			maximum_arguments: 2
			optional_call:     false
			computed:          false
		) {
			continue
		}
		callee := t.node(node, .callee) or { continue }
		object := t.node(callee, .object) or { continue }
		property := t.node(callee, .property) or { continue }
		if t.typ(property) != .identifier {
			continue
		}
		method := t.string_of(property, .name) or { continue }
		o := unacr_method(method) or { continue }
		if unacr_should_ignore_call(t, node, method, o, ignored_callees) {
			continue
		}
		mut callbacks := []int{}
		unacr_ternary_branches(t, (t.list(node, .arguments) or { continue })[0], mut callbacks)
		mut reportable := []int{}
		for callback in callbacks {
			typ := t.typ(callback)
			mut visited := map[int]bool{}
			if typ in [.function_expression, .arrow_function_expression, .call_expression]
				|| (typ == .identifier && (t.string_of(callback, .name) or { '' }) in o.ignore)
				|| c.unacr_is_definitely_not_function_value(root, t, callback, mut visited)
				|| un_is_node_value_not_function(t, callback)
				|| (method in ['every', 'filter', 'find', 'findLast']
				&& c.unacr_type_predicate_callback(root, t, callback)) {
				continue
			}
			reportable << callback
		}
		// Resolving the receiver type is expensive, so it runs last, after an inline callback has
		// already been ruled out
		if reportable.len == 0 || c.unb_is_known_non_target(t, object, unacr_receiver_type_options(), mut
			ctx) {
			continue
		}
		for callback in reportable {
			findings << c.unacr_problem(root, t, tokens, callback, node, method, o)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (mut c Checker) unacr_problem(root C.vt_node, t &estree.EsTree, tokens &SourceTokens, node int, call int, method string, o UnacrMethod) Finding {
	name := if t.typ(node) == .identifier { t.string_of(node, .name) or { '' } } else { '' }
	finding := Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: if name != '' { 'error-with-name' } else { 'error-without-name' }
		data:       {
			'name':   name
			'method': method
		}
	}
	if t.typ(node) in [.yield_expression, .await_expression] {
		return finding
	}
	all_parameters := unacr_suggestion_parameters(t, call, node, o.parameters)
	// A callback that declares more parameters than the method supplies still only receives what
	// the method passes, so the depth is capped by the method rather than by the declaration.
	declared := c.unacr_declared_parameter_count(root, t, node) or { o.min_parameters }
	shallowest := math.min(math.max(o.min_parameters, declared), all_parameters.len)
	mut text := c.un_parenthesized_text(t, tokens, node)
	starts_badly := if o.returns_undefined {
		c.unb_should_add_parens_to_expression_statement_expression(t, tokens, node)
	} else if first := un_first_token(t, tokens, node, 0) {
		c.token_text(first) == '{'
	} else {
		false
	}
	if !c.un_is_parenthesized(t, tokens, node) && (unb_call_callee_needs_parens(t, node)
		|| starts_badly) {
		text = '(${text})'
	}
	start, end := c.un_parenthesized_range(t, tokens, node)
	mut suggestions := []Suggestion{}
	for length in shallowest .. all_parameters.len + 1 {
		parameters := all_parameters[..length].join(', ')
		suggestions << Suggestion{
			message_id: if name != '' { 'replace-with-name' } else { 'replace-without-name' }
			data:       {
				'name':       name
				'parameters': parameters
			}
			fix:        fix_replace_range(start, end, if o.returns_undefined {
				'(${parameters}) => { ${text}(${parameters}); }'
			} else {
				'(${parameters}) => ${text}(${parameters})'
			})
		}
	}
	return Finding{
		...finding
		suggestions: suggestions
	}
}
