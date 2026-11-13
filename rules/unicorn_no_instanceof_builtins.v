module rules

import estree
import json2
import time

// Port of the `unicorn/no-instanceof-builtins` rule of eslint-plugin-unicorn 64.0.0, with its
// fixes and suggestions.

const unib_messages = {
	'no-instanceof-builtins': 'Avoid using `instanceof` for type checking as it can lead to unreliable results.'
	'switch-to-type-of':      "Switch to `typeof … === '{{type}}'`."
}

const unib_primitive_wrappers = ['String', 'Number', 'Boolean', 'BigInt', 'Symbol']

const unib_strict_constructors = ['Error', 'EvalError', 'RangeError', 'ReferenceError',
	'SyntaxError', 'TypeError', 'URIError', 'AggregateError', 'SuppressedError', 'Map', 'Set',
	'WeakMap', 'WeakRef', 'WeakSet', 'ArrayBuffer', 'Int8Array', 'Uint8Array', 'Uint8ClampedArray',
	'Int16Array', 'Uint16Array', 'Int32Array', 'Uint32Array', 'Float16Array', 'Float32Array',
	'Float64Array', 'BigInt64Array', 'BigUint64Array', 'Object', 'RegExp', 'Promise', 'Proxy',
	'DataView', 'Date', 'SharedArrayBuffer', 'FinalizationRegistry']

struct UnibOptions {
	use_error_is_error bool
	forbidden          []string
	exclude            []string
}

fn unib_strings(value json2.Any) []string {
	if value is []json2.Any {
		return value.map(it.str())
	}
	return []string{}
}

fn unib_options(options []json2.Any) !UnibOptions {
	o := option_object(unicorn_no_instanceof_builtins, options, ['useErrorIsError', 'strategy',
		'include', 'exclude'])!
	strategy := (o.values['strategy'] or { json2.Any('loose') }).str()
	include := unib_strings(o.values['include'] or { json2.Any([]json2.Any{}) })
	mut forbidden := if strategy == 'strict' { unib_strict_constructors.clone() } else { []string{} }
	forbidden << include
	return UnibOptions{
		use_error_is_error: o.bool_value('useErrorIsError')!
		forbidden:          forbidden
		exclude:            unib_strings(o.values['exclude'] or { json2.Any([]json2.Any{}) })
	}
}

fn (mut c Checker) lint_unicorn_no_instanceof_builtins(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	opts := unib_options(c.rule_options(unicorn_no_instanceof_builtins))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .binary_expression {
			continue
		}
		stats.checked++
		right := t.node(node, .right) or { continue }
		if (t.string_of(node, .operator) or { '' }) != 'instanceof' || t.typ(right) != .identifier {
			continue
		}
		name := t.string_of(right, .name) or { continue }
		if name in opts.exclude {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-instanceof-builtins'
		}
		if name == 'Array' || (name == 'Error' && opts.use_error_is_error) {
			function := if name == 'Array' { 'Array.isArray' } else { 'Error.isError' }
			has_fix, fix := c.merge_fixes(c.unib_function_call(t, tokens, node, function))!
			findings << Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
			continue
		}
		if name == 'Function' {
			has_fix, fix := c.merge_fixes(c.unib_type_of(t, tokens, node))!
			findings << Finding{
				...finding
				has_fix: has_fix
				fix:     fix
			}
			continue
		}
		if name in unib_primitive_wrappers {
			_, fix := c.merge_fixes(c.unib_type_of(t, tokens, node))!
			findings << Finding{
				...finding
				suggestions: [
					Suggestion{
						message_id: 'switch-to-type-of'
						data:       {
							'type': name.to_lower()
						}
						fix:        fix
					},
				]
			}
			continue
		}
		if name in opts.forbidden {
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unib_instanceof_token is the `instanceof` keyword after the left operand.
fn (c &Checker) unib_instanceof_token(t &estree.EsTree, tokens &SourceTokens, left int) ?SourceToken {
	for i := source_tokens_index(tokens.tokens, t.nodes[left].end); i < tokens.tokens.len; i++ {
		token := tokens.tokens[i]
		if token.kind == .keyword && c.token_text(token) == 'instanceof' {
			return token
		}
	}
	return none
}

// unib_function_call ports replaceWithFunctionCall: `a instanceof Array` becomes
// `Array.isArray(a)`.
fn (c &Checker) unib_function_call(t &estree.EsTree, tokens &SourceTokens, node int, function string) []Fix {
	left := t.node(node, .left) or { return [] }
	right := t.node(node, .right) or { return [] }
	keyword := c.unib_instanceof_token(t, tokens, left) or { return [] }
	mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
	start, end := c.un_parenthesized_range(t, tokens, left)
	fixes << fix_insert_at(start, function + '(')
	fixes << fix_insert_at(end, ')')
	fixes << c.un_replace_token_and_spaces_before(keyword, '')
	fixes << c.un_replace_node_and_spaces_before(t, tokens, right, '')
	return fixes
}

// unib_type_of ports replaceWithTypeOfExpression: `a instanceof String` becomes
// `typeof a === 'string'`.
fn (c &Checker) unib_type_of(t &estree.EsTree, tokens &SourceTokens, node int) []Fix {
	left := t.node(node, .left) or { return [] }
	right := t.node(node, .right) or { return [] }
	keyword := c.unib_instanceof_token(t, tokens, left) or { return [] }
	mut fixes := c.un_fix_space_around_keyword(t, tokens, node)
	left_start, _ := c.un_parenthesized_range(t, tokens, left)
	fixes << fix_insert_at(left_start, 'typeof ')
	fixes << fix_replace_range(keyword.start, keyword.end, '===')
	right_start, right_end := c.un_parenthesized_range(t, tokens, right)
	fixes << fix_replace_range(right_start, right_end, "'" + c.un_text(t, right).to_lower() + "'")
	return fixes
}
