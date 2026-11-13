module rules

import json2
import jsregexp
import time
import treesitter { named_children, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `object-shorthand` rule of ESLint 10.6.0, with its options and its fixes.

const os_messages = {
	'expectedAllPropertiesShorthanded': 'Expected shorthand for all properties.'
	'expectedLiteralMethodLongform':    'Expected longform method syntax for string literal keys.'
	'expectedPropertyShorthand':        'Expected property shorthand.'
	'expectedPropertyLongform':         'Expected longform property syntax.'
	'expectedMethodShorthand':          'Expected method shorthand.'
	'expectedMethodLongform':           'Expected longform method syntax.'
	'unexpectedMix':                    'Unexpected mix of shorthand and non-shorthand properties.'
}

// The functions whose `this`, `super`, `new.target` and `arguments` are their own.
const os_function_kinds = ['function_declaration', 'function_expression', 'generator_function',
	'generator_function_declaration', 'method_definition']

struct OsOptions {
	apply                        string
	ignore_constructors          bool
	methods_ignore               ?jsregexp.RegexpProgram
	avoid_quotes                 bool
	avoid_explicit_return_arrows bool
}

// os_options reads the mode and the object of its options.
fn os_options(options []json2.Any) !OsOptions {
	apply := if options.len > 0 { options[0] } else { json2.Any('always') }
	if apply !is string || apply.str() !in ['always', 'methods', 'properties', 'never', 'consistent',
		'consistent-as-needed'] {
		return error('the first option of `${object_shorthand}` is not one of its values')
	}
	o := option_object(object_shorthand, if options.len > 1 { options[1..] } else { []json2.Any{} },
		['ignoreConstructors', 'methodsIgnorePattern', 'avoidQuotes', 'avoidExplicitReturnArrows'])!
	pattern := o.values['methodsIgnorePattern'] or { json2.Any('') }
	mut program := ?jsregexp.RegexpProgram(none)
	if pattern is string && pattern.str() != '' {
		program = jsregexp.regexp_compile(pattern.str()) or {
			return error('`methodsIgnorePattern` of `${object_shorthand}` is not a valid regular expression')
		}
	}
	return OsOptions{
		apply:                        apply.str()
		ignore_constructors:          o.bool_value('ignoreConstructors') or { false }
		methods_ignore:               program
		avoid_quotes:                 o.bool_value('avoidQuotes') or { false }
		avoid_explicit_return_arrows: o.bool_value('avoidExplicitReturnArrows') or { false }
	}
}

fn (mut c Checker) lint_object_shorthand(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := os_options(c.rule_options(object_shorthand))!
	mut findings := []Finding{}
	for object in c.nodes_of_kinds(root, ['object'], []) {
		stats.checked++
		properties := named_children(object).filter(node_kind(it) in ['pair', 'method_definition',
			'shorthand_property_identifier', 'spread_element'])
		if o.apply in ['consistent', 'consistent-as-needed'] {
			c.os_consistency(object, properties, o.apply == 'consistent-as-needed', mut findings)
		}
		for property in properties {
			c.os_property(root, o, property, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// os_consistency ports checkConsistency.
fn (mut c Checker) os_consistency(object C.TSNode, all []C.TSNode, check_redundancy bool, mut findings []Finding) {
	properties := all.filter(node_kind(it) != 'spread_element' && es_accessor_kind(it) == 'init')
	if properties.len == 0 {
		return
	}
	shorthand := properties.filter(node_kind(it) != 'pair').len
	if shorthand == properties.len {
		return
	}
	if shorthand > 0 {
		findings << Finding{
			stmt:       position_of(object)
			message_id: 'unexpectedMix'
		}
	} else if check_redundancy && properties.all(c.os_is_redundant(it)) {
		findings << Finding{
			stmt:       position_of(object)
			message_id: 'expectedAllPropertiesShorthanded'
		}
	}
}

// os_is_redundant ports isRedundant: an anonymous function, or an identifier named as the key.
fn (c &Checker) os_is_redundant(property C.TSNode) bool {
	value := unwrap_parens(node_field(property, 'value') or { return false })
	match node_kind(value) {
		'function_expression', 'generator_function' {
			return es_function_id(value) == none
		}
		'identifier', 'undefined' {
			name := c.es_static_key_name(property) or { return false }
			return name == c.identifier_name(value)
		}
		else {
			return false
		}
	}
}

// os_property is the check of a Property at its exit.
fn (mut c Checker) os_property(root C.TSNode, o OsOptions, property C.TSNode, mut findings []Finding) {
	kind := node_kind(property)
	if kind == 'spread_element' || es_accessor_kind(property) != 'init' {
		return
	}
	key, computed := es_property_key(property) or { return }
	value := if kind == 'pair' {
		unwrap_parens(node_field(property, 'value') or { return })
	} else {
		property
	}
	value_kind := node_kind(value)
	is_function := value_kind in ['function_expression', 'generator_function', 'arrow_function']
		|| kind == 'method_definition'
	if computed && !is_function {
		return
	}
	key_is_string := !computed && node_kind(key) == 'string'
	never := o.apply == 'never'
	if kind == 'method_definition' {
		if never || (o.avoid_quotes && node_kind(key) == 'string') {
			has_fix, fix := c.os_longform_fix(root, property, key, computed)
			findings << Finding{
				stmt:       position_of(property)
				message_id: if never {
					'expectedMethodLongform'
				} else {
					'expectedLiteralMethodLongform'
				}
				has_fix:    has_fix
				fix:        fix
			}
		}
		return
	}
	if kind == 'shorthand_property_identifier' {
		if never {
			findings << Finding{
				stmt:       position_of(property)
				message_id: 'expectedPropertyLongform'
				has_fix:    true
				fix:        fix_insert_at(c.es_end(key), ': ${c.text(key)}')
			}
		}
		return
	}
	to_methods := o.apply in ['methods', 'always']
	to_props := o.apply in ['properties', 'always']
	if to_methods && is_function && es_function_id(value) == none {
		if o.ignore_constructors && node_kind(key) in ['property_identifier', 'identifier']
			&& os_is_constructor(c.text(key)) {
			return
		}
		if program := o.methods_ignore {
			if name := c.es_static_key_name(property) {
				if jsregexp.regexp_test(program, name) or { false } {
					return
				}
			}
		}
		if o.avoid_quotes && node_kind(key) == 'string' {
			return
		}
		if value_kind != 'arrow_function' || (o.avoid_explicit_return_arrows
			&& node_kind(node_field(value, 'body') or { value }) == 'statement_block'
			&& !c.os_has_lexical_identifiers(root, value)) {
			has_fix, fix := c.os_shorthand_fix(root, property, key, computed, value)
			findings << Finding{
				stmt:       position_of(property)
				message_id: 'expectedMethodShorthand'
				has_fix:    has_fix
				fix:        fix
			}
		}
		return
	}
	if value_kind !in ['identifier', 'undefined'] || !to_props {
		return
	}
	value_name := c.identifier_name(value)
	tokens := c.source_tokens(root)
	comments := tokens.comments_inside(node_start(property), c.es_end(property))
	if node_kind(key) == 'property_identifier' && c.text(key) == value_name {
		for comment in comments {
			text := c.src[comment.start..comment.end]
			if comment.kind == .block_comment && text.len >= 4
				&& text[2..text.len - 2].trim_left(' \t\n\r\v\f').starts_with('*')
				&& text.contains('@type') {
				return
			}
		}
	} else if key_is_string && (c.literal_name(key) or { '' }) == value_name {
		if o.avoid_quotes {
			return
		}
		for comment in comments {
			text := c.src[comment.start..comment.end]
			if comment.kind == .block_comment && text.starts_with('/**') && text.contains('@type') {
				return
			}
		}
	} else {
		return
	}
	findings << Finding{
		stmt:       position_of(property)
		message_id: 'expectedPropertyShorthand'
		has_fix:    comments.len == 0
		fix:        fix_replace_range(node_start(property), c.es_end(property), value_name)
	}
}

// os_is_constructor ports isConstructor: the first character that is not `_`, `$` or a digit is
// the same in upper case.
fn os_is_constructor(name string) bool {
	units := utf16_units(name)
	for i, unit in units {
		if unit == `_` || unit == `$` || (unit >= `0` && unit <= `9`) {
			continue
		}
		return jsregexp.js_to_upper(units[i..i + 1]) == units[i..i + 1]
	}
	return false
}

// os_has_lexical_identifiers: the arrow uses the `this`, `super`, `new.target` or `arguments` of
// the function around it.
fn (mut c Checker) os_has_lexical_identifiers(root C.TSNode, arrow C.TSNode) bool {
	for n in c.nodes_of_kinds(arrow, ['this', 'super', 'meta_property', 'identifier'], os_function_kinds) {
		match node_kind(n) {
			'this', 'super' {
				return true
			}
			'meta_property' {
				if c.text(n).replace(' ', '') == 'new.target' {
					return true
				}
			}
			else {
				if c.text(n) != 'arguments' {
					continue
				}
				tree := c.scope_tree(root)
				key := node_key(n)
				for v in tree.variables {
					if v.name == 'arguments' && v.defs.len == 0 && tree.scopes[v.scope].kind == .function
						&& v.references.any(node_key(tree.references[it].identifier) == key) {
						return true
					}
				}
			}
		}
	}
	return false
}

// os_key_tokens are the first and last tokens of the key, with the brackets of a computed one.
fn (mut c Checker) os_key_tokens(root C.TSNode, property C.TSNode, key C.TSNode, computed bool) ?(SourceToken, SourceToken) {
	tokens := c.source_tokens(root)
	if !computed {
		return tokens.after(node_start(key), false)?, tokens.before(c.es_end(key), false)?
	}
	mut first := tokens.after(node_start(property), false)?
	for c.src[first.start..first.end] != '[' {
		first = tokens.after(first.end, false)?
	}
	mut last := tokens.after(c.es_end(key), false)?
	for c.src[last.start..last.end] != ']' {
		last = tokens.after(last.end, false)?
	}
	return first, last
}

// os_longform_fix ports makeFunctionLongform: `key: function`.
fn (mut c Checker) os_longform_fix(root C.TSNode, method C.TSNode, key C.TSNode, computed bool) (bool, Fix) {
	first, last := c.os_key_tokens(root, method, key, computed) or { return false, Fix{} }
	mut header := 'function'
	if es_is_async_function(method) {
		header = 'async ${header}'
	}
	if es_is_generator_function(method) {
		header = '${header}*'
	}
	return true, fix_replace_range(node_start(method), last.end, '${c.src[first.start..last.end]}: ${header}')
}

// os_shorthand_fix ports makeFunctionShorthand: `key(params) {…}`.
fn (mut c Checker) os_shorthand_fix(root C.TSNode, property C.TSNode, key C.TSNode, computed bool, value C.TSNode) (bool, Fix) {
	tokens := c.source_tokens(root)
	first, last := c.os_key_tokens(root, property, key, computed) or { return false, Fix{} }
	if tokens.comments_exist_between(last.end, node_start(value)) {
		return false, Fix{}
	}
	mut prefix := ''
	if es_is_async_function(value) {
		prefix += 'async '
	}
	if es_is_generator_function(value) {
		prefix += '*'
	}
	prefix += c.src[first.start..last.end]
	value_end := c.es_end(value)
	fix_end := c.es_end(property)
	if node_kind(value) != 'arrow_function' {
		mut function_token := tokens.after(node_start(value), false) or { return false, Fix{} }
		for !(function_token.kind == .keyword && c.src[function_token.start..function_token.end] == 'function') {
			function_token = tokens.after(function_token.end, false) or { return false, Fix{} }
		}
		before_params := if es_is_generator_function(value) {
			tokens.after(function_token.end, false) or { return false, Fix{} }
		} else {
			function_token
		}
		return true, fix_replace_range(first.start, fix_end, prefix + c.src[before_params.end..value_end])
	}
	body := node_field(value, 'body') or { return false, Fix{} }
	mut arrow_token := tokens.before(node_start(body), false) or { return false, Fix{} }
	for c.src[arrow_token.start..arrow_token.end] != '=>' {
		arrow_token = tokens.before(arrow_token.start, false) or { return false, Fix{} }
	}
	mut first_value := tokens.after(node_start(value), false) or { return false, Fix{} }
	if es_is_async_function(value) {
		first_value = tokens.after(first_value.end, false) or { return false, Fix{} }
	}
	slice_end := (tokens.before(arrow_token.start, false) or { return false, Fix{} }).end
	old := c.src[first_value.start..slice_end]
	add_parens := if parameter := node_field(value, 'parameter') {
		node_start(parameter) == first_value.start
	} else {
		false
	}
	params := if add_parens { '(${old})' } else { old }
	return true, fix_replace_range(first.start, fix_end, prefix + params + c.src[arrow_token.end..value_end])
}
