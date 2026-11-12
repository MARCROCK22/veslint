module rules

import json2
import time
import tsgo { TypeResponse, handle_kind }
import treesitter { named_children, node_kind, node_parent, nodes_of_kind, position_of }

// Port of the `no-misused-spread` rule of typescript-eslint 8.62.0, with its `allow` option (bare
// names and `from: "lib"` specifiers) and its `addAwait` and `replaceMapSpreadInObject` suggestions.

const nms_messages = {
	'addAwait':                         'Add await operator.'
	'noArraySpreadInObject':            'Using the spread operator on an array in an object will result in a list of indices.'
	'noClassDeclarationSpreadInObject': 'Using the spread operator on class declarations will spread only their static properties, and will lose their class prototype.'
	'noClassInstanceSpreadInObject':    'Using the spread operator on class instances will lose their class prototype.'
	'noFunctionSpreadInObject':         'Using the spread operator on a function without additional properties can cause unexpected behavior. Did you forget to call the function?'
	'noIterableSpreadInObject':         'Using the spread operator on an Iterable in an object can cause unexpected behavior.'
	'noMapSpreadInObject':              'Using the spread operator on a Map in an object will result in an empty object. Did you mean to use `Object.fromEntries(map)` instead?'
	'noPromiseSpreadInObject':          'Using the spread operator on Promise in an object can cause unexpected behavior. Did you forget to await the promise?'
	'noStringSpread':                   'Using the spread operator on a string can mishandle special characters, as can `.split("")`.\n- `...` produces Unicode code points, which will decompose complex emojis into individual emojis\n- .split("") produces UTF-16 code units, which breaks rich characters in many languages\nConsider using `Intl.Segmenter` for locale-aware string decomposition.\nOtherwise, if you don\'t need to preserve emojis or other non-Ascii characters, disable this lint rule on this line or configure the \'allow\' rule option.'
	'replaceMapSpreadInObject':         'Replace map spread in object with `Object.fromEntries()`'
}

// ObjectFlags.InstantiationExpressionType of TypeScript 7.1.0-beta.
const nms_instantiation_expression_type = u32(16777216)

// The global symbols of isBuiltinSymbolLike(…, ['Map', 'ReadonlyMap', 'WeakMap']).
const nms_map_names = ['Map', 'ReadonlyMap', 'WeakMap']

struct NmsOptions {
	allow []TypeSpecifier
}

fn nms_options(options []json2.Any) !NmsOptions {
	o := option_object(no_misused_spread, options, ['allow'])!
	return NmsOptions{
		allow: o.specifiers('allow')!
	}
}

// NmsSpread is a SpreadElement: in an array or the arguments of a call (`in_object` false) or in
// an object literal.
struct NmsSpread {
	node      C.TSNode
	argument  C.TSNode
	in_object bool
}

// NmsPredicate names the predicates the rule gives isTypeRecurser.
enum NmsPredicate {
	string
	function_without_props
	promise
	map
	array
	class_instance
	class_declaration
}

fn (mut c Checker) lint_no_misused_spread(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := nms_options(c.rule_options(no_misused_spread))!
	mut spreads := []NmsSpread{}
	for node in c.nodes_of_kind(root, c'spread_element') {
		parent := node_parent(node) or { continue }
		in_object := match node_kind(parent) {
			'array' {
				false
			}
			'arguments' {
				// `CallExpression > SpreadElement`: not the arguments of a `new`.
				call := node_parent(parent) or { continue }
				if node_kind(call) != 'call_expression' {
					continue
				}
				false
			}
			'object' {
				true
			}
			'jsx_expression' {
				// JSXSpreadAttribute: `<a {...x} />`. A spread among the children of an element is a
				// JSXSpreadChild, which the rule does not look at.
				element := node_parent(parent) or { continue }
				if node_kind(element) !in ['jsx_opening_element', 'jsx_self_closing_element'] {
					continue
				}
				true
			}
			else {
				continue
			}
		}
		spreads << NmsSpread{
			// A JSXSpreadAttribute is the whole `{...x}`.
			node:      if node_kind(parent) == 'jsx_expression' { parent } else { node }
			argument:  unwrap_parens(first_named(node) or { continue })
			in_object: in_object
		}
	}
	c.resolve_spans(spreads.map(node_span(it.argument)), abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for spread in spreads {
		t := c.node_type(spread.argument) or { continue }
		constrained := c.constrained(t)!
		if c.type_matches_some_specifier(constrained, o.allow)! {
			continue
		}
		message_id := if spread.in_object {
			c.nms_object_spread(constrained, nms_map_names)!
		} else if c.nms_recurse(constrained, .string, nms_map_names, 0)! {
			'noStringSpread'
		} else {
			''
		}
		if message_id == '' {
			continue
		}
		mut suggestions := []Suggestion{}
		if message_id == 'noPromiseSpreadInObject' {
			_, suggestion := c.suggestion('addAwait', map[string]string{}, nms_add_await(spread.argument))!
			suggestions << suggestion
		} else if message_id == 'noMapSpreadInObject' {
			suggestions << c.nms_map_suggestions(spread, constrained, nms_map_names)!
		}
		findings << Finding{
			stmt:        position_of(spread.node)
			message_id:  message_id
			suggestions: suggestions
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += spreads.len
	return findings
}

// nms_add_await ports the fixer of getPromiseSpreadSuggestions: `await ` before the argument of the
// spread, in parentheses unless its precedence is higher than that of `await`.
fn nms_add_await(argument C.TSNode) []Fix {
	if is_higher_precedence_than_await(argument) {
		return [fix_insert_before(argument, 'await ')]
	}
	return [fix_insert_before(argument, 'await ('), fix_insert_after(argument, ')')]
}

// nms_map_suggestions ports getMapSpreadSuggestions: none unless every part of the union is a Map;
// else `Object.fromEntries(map)` takes the place of the whole object, if the spread is its only
// property, or of the argument of the spread (getWrappingFixer).
fn (mut c Checker) nms_map_suggestions(spread NmsSpread, t TypeResponse, map_symbols []string) ![]Suggestion {
	for part in c.constituents(t)! {
		if !c.nms_recurse(part, .map, map_symbols, 0)! {
			return []Suggestion{}
		}
	}
	argument := es_child(spread.argument)
	mut node := argument
	if object := node_parent(spread.node) {
		if node_kind(object) == 'object' && named_children(object).len == 1 {
			node = es_child(object)
		}
	}
	code := c.wrapping_inner_code(node, argument)
	fix := c.wrapping_fix(node, 'Object.fromEntries(${code})')
	ok, suggestion := c.suggestion('replaceMapSpreadInObject', map[string]string{}, [fix])!
	return if ok { [suggestion] } else { []Suggestion{} }
}

// nms_object_spread ports checkObjectSpread: the message for a spread in an object, or ''.
fn (mut c Checker) nms_object_spread(t TypeResponse, map_symbols []string) !string {
	if c.nms_recurse(t, .promise, map_symbols, 0)! {
		return 'noPromiseSpreadInObject'
	}
	if c.nms_recurse(t, .function_without_props, map_symbols, 0)! {
		return 'noFunctionSpreadInObject'
	}
	if c.nms_recurse(t, .map, map_symbols, 0)! {
		return 'noMapSpreadInObject'
	}
	if c.nms_recurse(t, .array, map_symbols, 0)! {
		return 'noArraySpreadInObject'
	}
	if c.nms_is_iterable(t)! && !c.nms_recurse(t, .string, map_symbols, 0)! {
		return 'noIterableSpreadInObject'
	}
	if c.nms_recurse(t, .class_instance, map_symbols, 0)! {
		return 'noClassInstanceSpreadInObject'
	}
	if c.nms_recurse(t, .class_declaration, map_symbols, 0)! {
		return 'noClassDeclarationSpreadInObject'
	}
	return ''
}

// nms_recurse ports isTypeRecurser: some part of a union or an intersection (recursively) satisfies
// the predicate.
fn (mut c Checker) nms_recurse(t TypeResponse, predicate NmsPredicate, map_symbols []string, depth int) !bool {
	if t.flags & (type_flag_union | type_flag_intersection) != 0 {
		if depth >= max_type_depth {
			return false
		}
		for part in c.members_of(t)! {
			if c.nms_recurse(part, predicate, map_symbols, depth + 1)! {
				return true
			}
		}
		return false
	}
	return match predicate {
		.string {
			// util.isTypeFlagSet: union-aware, but `t` is not a union here.
			t.flags & type_flag_string_like != 0
		}
		.function_without_props {
			c.signatures_of(t, signature_kind_call)!.len > 0 && c.properties(t)!.len == 0
		}
		.promise {
			c.builtin_promise(t, 0)!
		}
		.map {
			c.builtin_symbol_like_any(t, map_symbols, 0)!
		}
		.array {
			c.is_array(t)! || c.is_tuple(t)!
		}
		.class_instance {
			c.nms_is_class_instance(t)!
		}
		.class_declaration {
			c.nms_is_class_declaration(t)!
		}
	}
}

// nms_is_iterable ports isIterable: a part of the union or intersection (one level, typeConstituents)
// has a `[Symbol.iterator]` property.
fn (mut c Checker) nms_is_iterable(t TypeResponse) !bool {
	for part in c.type_constituents(t)! {
		if c.has_well_known_property(part, 'iterator')! {
			return true
		}
	}
	return false
}

// nms_is_class_instance ports isClassInstance: the type has no construct signatures and its symbol,
// seen from some of its declarations, does.
fn (mut c Checker) nms_is_class_instance(t TypeResponse) !bool {
	if c.signatures_of(t, signature_kind_construct)!.len > 0 {
		return false
	}
	symbol := c.symbol_of(t)!
	if symbol.is_null() {
		return false
	}
	for declaration in symbol.declarations {
		seen := c.client.type_of_symbol_at_location(c.snapshot, c.project, symbol.id, declaration)!
		if !seen.is_null() && c.signatures_of(seen, signature_kind_construct)!.len > 0 {
			return true
		}
	}
	return false
}

// nms_is_class_declaration ports isClassDeclaration: an instantiation expression type, or a type
// whose symbol's value declaration is a class.
fn (mut c Checker) nms_is_class_declaration(t TypeResponse) !bool {
	if t.flags & type_flag_object != 0 && t.object_flags & nms_instantiation_expression_type != 0 {
		return true
	}
	symbol := c.symbol_of(t)!
	if symbol.is_null() || symbol.value_declaration == '' {
		return false
	}
	kind := handle_kind(symbol.value_declaration)
	return kind == syntax_kind_class_declaration || kind == syntax_kind_class_expression
}
