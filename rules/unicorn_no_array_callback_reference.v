module rules

import estree
import time

// Port of the `unicorn/no-array-callback-reference` rule of eslint-plugin-unicorn 64.0.0 (it has no
// options), with its suggestions.

const unacr_messages = {
	'error-with-name':      'Do not pass function `{{name}}` directly to `.{{method}}(…)`.'
	'error-without-name':   'Do not pass function directly to `.{{method}}(…)`.'
	'replace-with-name':    'Replace function `{{name}}` with `… => {{name}}({{parameters}})`.'
	'replace-without-name': 'Replace function with `… => …({{parameters}})`.'
}

const unacr_ignored_callee = ['Promise', 'React.Children', 'Children', 'lodash', 'underscore', '_',
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

fn unacr_should_ignore_call(t &estree.EsTree, call int, method string, o UnacrMethod) bool {
	parent := t.nodes[call].parent
	if method !in ['reduce', 'reduceRight'] && parent >= 0 && t.typ(parent) == .await_expression
		&& t.node(parent, .argument) or { -1 } == call {
		return true
	}
	object := t.node(t.node(call, .callee) or { return false }, .object) or { return false }
	if un_is_node_matches(t, object, unacr_ignored_callee) {
		return true
	}
	if t.typ(object) == .call_expression
		&& un_is_node_matches(t, t.node(object, .callee) or { -1 }, unacr_ignored_callee) {
		return true
	}
	return o.ignored_object != '' && t.typ(object) == .identifier
		&& (t.string_of(object, .name) or { '' }) == o.ignored_object
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
fn (mut c Checker) unacr_type_predicate_callback(root C.TSNode, t &estree.EsTree, callback int) bool {
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

fn (mut c Checker) lint_unicorn_no_array_callback_reference(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
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
		property := t.node(t.node(node, .callee) or { continue }, .property) or { continue }
		if t.typ(property) != .identifier {
			continue
		}
		method := t.string_of(property, .name) or { continue }
		o := unacr_method(method) or { continue }
		if unacr_should_ignore_call(t, node, method, o) {
			continue
		}
		mut callbacks := []int{}
		unacr_ternary_branches(t, (t.list(node, .arguments) or { continue })[0], mut callbacks)
		for callback in callbacks {
			typ := t.typ(callback)
			if typ in [.function_expression, .arrow_function_expression, .call_expression]
				|| (typ == .identifier && (t.string_of(callback, .name) or { '' }) in o.ignore)
				|| un_is_node_value_not_function(t, callback)
				|| (method in ['every', 'filter', 'find', 'findLast']
				&& c.unacr_type_predicate_callback(root, t, callback)) {
				continue
			}
			findings << c.unacr_problem(t, tokens, callback, method, o)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn (c &Checker) unacr_problem(t &estree.EsTree, tokens &SourceTokens, node int, method string, o UnacrMethod) Finding {
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
	mut text := c.un_parenthesized_text(t, tokens, node)
	if !c.un_is_parenthesized(t, tokens, node) && un_call_callee_needs_parens(t, node) {
		text = '(${text})'
	}
	start, end := c.un_parenthesized_range(t, tokens, node)
	mut suggestions := []Suggestion{}
	for length in o.min_parameters .. o.parameters.len + 1 {
		parameters := o.parameters[..length].join(', ')
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
