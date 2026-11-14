module rules

import estree
import json2
import time

// Port of the `unicorn/no-instanceof-builtins` rule of eslint-plugin-unicorn 79.0.0, with its
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
		if (t.string_of(node, .operator) or { '' }) != 'instanceof' {
			continue
		}
		name, reference_text := c.unib_constructor(root, t, right) or { continue }
		if name in opts.exclude {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-instanceof-builtins'
		}
		left := t.node(node, .left) or { continue }
		// Comments outside the kept left operand could be lost or moved.
		commented := c.unb_would_remove_comments(tokens, unb_node_range(t, node), [
			c.unb_parenthesized_range(t, tokens, left),
		], false)
		if name == 'Array' || (name == 'Error' && opts.use_error_is_error) {
			function := reference_text + if name == 'Array' { '.isArray' } else { '.isError' }
			if !commented {
				has_fix, fix := c.merge_fixes(c.unib_function_call(t, tokens, node, function))!
				finding = Finding{
					...finding
					has_fix: has_fix
					fix:     fix
				}
			}
			findings << finding
			continue
		}
		if name == 'Function' {
			if !commented {
				if fixes := c.unib_type_of(t, tokens, node, name) {
					has_fix, fix := c.merge_fixes(fixes)!
					finding = Finding{
						...finding
						has_fix: has_fix
						fix:     fix
					}
				}
			}
			findings << finding
			continue
		}
		if name in unib_primitive_wrappers {
			if !commented {
				if fixes := c.unib_type_of(t, tokens, node, name) {
					_, fix := c.merge_fixes(fixes)!
					finding = Finding{
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
				}
			}
			findings << finding
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

// unib_constructor ports getConstructor: the name of the constructor and how it is written, for
// `Name` or `global.Name` (`globalThis`, `self` and `window` too) of the global object.
fn (mut c Checker) unib_constructor(root C.TSNode, t &estree.EsTree, node int) ?(string, string) {
	if t.typ(node) == .identifier {
		name := t.string_of(node, .name)?
		return name, name
	}
	if t.typ(node) != .member_expression || (t.flag(node, .computed) or { false }) {
		return none
	}
	property := t.node(node, .property)?
	object := t.node(node, .object)?
	if t.typ(property) != .identifier || t.typ(object) != .identifier
		|| (t.string_of(object, .name) or { '' }) !in ['global', 'globalThis', 'self', 'window']
		|| !c.unb_is_global_identifier(root, t, object) {
		return none
	}
	return t.string_of(property, .name)?, c.un_text(t, node)
}

// unib_function_call ports replaceWithFunctionCall: `a instanceof Array` becomes
// `Array.isArray(a)`.
fn (c &Checker) unib_function_call(t &estree.EsTree, tokens &SourceTokens, node int, function string) []Fix {
	left := t.node(node, .left) or { return [] }
	right := t.node(node, .right) or { return [] }
	keyword := c.unib_instanceof_token(t, tokens, left) or { return [] }
	mut fixes := c.unb_fix_space_around_keyword(t, tokens, node)
	start, end := c.un_parenthesized_range(t, tokens, left)
	fixes << fix_insert_at(start, function + '(')
	fixes << fix_insert_at(end, ')')
	fixes << c.un_replace_token_and_spaces_before(keyword, '')
	fixes << c.un_replace_node_and_spaces_before(t, tokens, right, '')
	return fixes
}

// unib_type_of ports replaceWithTypeOfExpression: `a instanceof String` becomes
// `typeof a === 'string'`, in parentheses where the comparison binds more loosely.
fn (c &Checker) unib_type_of(t &estree.EsTree, tokens &SourceTokens, node int, constructor_name string) ?[]Fix {
	left := t.node(node, .left)?
	right := t.node(node, .right)?
	keyword := c.unib_instanceof_token(t, tokens, left)?
	needs_parens := c.unb_should_add_parens_to_comparison(t, tokens, node, '===')
	mut fixes := c.unb_fix_space_around_keyword(t, tokens, node)
	left_start, left_end := c.un_parenthesized_range(t, tokens, left)
	mut prefix := if needs_parens { '(' } else { '' }
	if c.unb_needs_semicolon(t, tokens, tokens.before(t.nodes[node].start, false), prefix) {
		prefix = ';' + prefix
	}
	// A left operand that binds more loosely gets parentheses: `typeof (a + b) === 'function'`.
	if !c.un_is_parenthesized(t, tokens, left) && unb_should_add_parens_to_unary_argument(t, left) {
		fixes << fix_insert_at(left_start, prefix + 'typeof (')
		fixes << fix_insert_at(left_end, ')')
	} else {
		fixes << fix_insert_at(left_start, prefix + 'typeof ')
	}
	fixes << fix_replace_range(keyword.start, keyword.end, '===')
	right_start, right_end := c.un_parenthesized_range(t, tokens, right)
	fixes << fix_replace_range(right_start, right_end, "'" + constructor_name.to_lower() + "'" + if needs_parens {
		')'
	} else {
		''
	})
	return fixes
}
