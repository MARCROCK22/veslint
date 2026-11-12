module rules

import json2
import math
import time
import tsgo { TypeResponse }
import treesitter { node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `prefer-destructuring` rule of typescript-eslint 8.62.0, which extends the rule of
// ESLint 10.6.0 with the same name, with its options and its fixer.
//
// The core rule reads the options as they were written, without typescript-eslint's defaults,
// and the extension reads them merged with those defaults: effective_options keeps both (the
// written ones are the third element).

const pd_messages = {
	'preferDestructuring': 'Use {{type}} destructuring.'
}

// TypeScript nodes that ESLint's getPrecedence does not know: it gives them the lowest
// precedence.
const pd_unknown_precedence_kinds = ['as_expression', 'satisfies_expression', 'non_null_expression',
	'type_assertion', 'instantiation_expression']

struct PdEnabled {
	array  bool
	object bool
}

struct PdOptions {
	// The options with the defaults: getNormalizedEnabledType and the two flags.
	typed_object                                 map[string]bool // by node type
	enforce_for_declaration_with_type_annotation bool
	enforce_for_renamed_properties               bool
	// The options as written: normalizedOptions and enforceForRenamedProperties of the core rule.
	core                                map[string]PdEnabled // by node type
	core_enforce_for_renamed_properties bool
}

const pd_node_types = ['VariableDeclarator', 'AssignmentExpression']

fn pd_bool(object map[string]json2.Any, key string) !bool {
	value := object[key] or { return false }
	if value !is bool {
		return error('`${key}` of `${prefer_destructuring}` must be true or false')
	}
	return value as bool
}

fn pd_object(value json2.Any, what string) !map[string]json2.Any {
	if value !is map[string]json2.Any {
		return error('${what} of `${prefer_destructuring}` must be an object')
	}
	return value.as_map()
}

fn pd_options(options []json2.Any) !PdOptions {
	mut typed_object := map[string]bool{}
	mut core := map[string]PdEnabled{}
	for node_type in pd_node_types {
		core[node_type] = PdEnabled{
			array:  true
			object: true
		}
	}
	mut flags := map[string]json2.Any{}
	if options.len > 0 {
		enabled := pd_object(options[0], 'the first option')!
		for key, _ in enabled {
			if key !in ['array', 'object', 'VariableDeclarator', 'AssignmentExpression'] {
				return error('`${prefer_destructuring}` has no option `${key}`')
			}
		}
		flat := 'object' in enabled || 'array' in enabled
		for node_type in pd_node_types {
			typed_object[node_type] = if flat {
				pd_bool(enabled, 'object')!
			} else if by_type := enabled[node_type] {
				pd_bool(pd_object(by_type, '`${node_type}`')!, 'object')!
			} else {
				false
			}
		}
	}
	if options.len > 1 {
		flags = pd_object(options[1], 'the second option')!.clone()
		for key, _ in flags {
			if key !in ['enforceForDeclarationWithTypeAnnotation', 'enforceForRenamedProperties'] {
				return error('`${prefer_destructuring}` has no option `${key}`')
			}
		}
	}
	// The options as they were written.
	mut core_renamed := false
	if options.len > 2 && options[2] is []json2.Any {
		written := options[2].as_array()
		if written.len > 0 {
			enabled := pd_object(written[0], 'the first option')!
			flat := 'object' in enabled || 'array' in enabled
			// The schema of the first option is a `oneOf`: the two shapes cannot be mixed, and an
			// empty object matches both.
			if enabled.len == 0 || (flat && ('VariableDeclarator' in enabled
				|| 'AssignmentExpression' in enabled)) {
				return error('the first option of `${prefer_destructuring}` must have either `array` and `object`, or `VariableDeclarator` and `AssignmentExpression`')
			}
			for node_type in pd_node_types {
				mut source := map[string]json2.Any{}
				if flat {
					source = enabled.clone()
				} else if by_type := enabled[node_type] {
					source = pd_object(by_type, '`${node_type}`')!.clone()
				}
				core[node_type] = PdEnabled{
					array:  pd_bool(source, 'array')!
					object: pd_bool(source, 'object')!
				}
			}
		}
		if written.len > 1 {
			core_renamed = pd_bool(pd_object(written[1], 'the second option')!, 'enforceForRenamedProperties')!
		}
	}
	return PdOptions{
		typed_object:                                 typed_object
		enforce_for_declaration_with_type_annotation: pd_bool(flags, 'enforceForDeclarationWithTypeAnnotation')!
		enforce_for_renamed_properties:               pd_bool(flags, 'enforceForRenamedProperties')!
		core:                                         core
		core_enforce_for_renamed_properties:          core_renamed
	}
}

// PdCheck is a VariableDeclarator or an AssignmentExpression with `=`.
struct PdCheck {
	node           C.TSNode
	node_type      string
	left           C.TSNode
	right          ?C.TSNode
	has_annotation bool
	is_using       bool
}

fn (mut c Checker) lint_prefer_destructuring(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	options := pd_options(c.rule_options(prefer_destructuring))!
	mut sw := time.new_stopwatch()
	mut checks := []PdCheck{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, ['variable_declarator', 'assignment_expression'],
		[]string{}) {
		mut check := PdCheck{}
		if node_kind(node) == 'variable_declarator' {
			left := node_field(node, 'name') or { continue }
			mut right := ?C.TSNode(none)
			if value := node_field(node, 'value') {
				right = unwrap_parens(value)
			}
			mut is_using := false
			if parent := node_parent(node) {
				is_using = using_kind(parent) != ''
			}
			check = PdCheck{
				node:           node
				node_type:      'VariableDeclarator'
				left:           left
				right:          right
				has_annotation: node_field(node, 'type') != none
				is_using:       is_using
			}
		} else {
			left := node_field(node, 'left') or { continue }
			right := node_field(node, 'right') or { continue }
			check = PdCheck{
				node:      node
				node_type: 'AssignmentExpression'
				left:      unwrap_parens(left)
				right:     unwrap_parens(right)
			}
		}
		checks << check
		if right := check.right {
			if pd_is_member(right) && c.pd_is_integer_index(right) {
				if object := node_field(right, 'object') {
					spans << node_span(unwrap_parens(object))
				}
			}
		}
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for check in checks {
		left_kind := node_kind(check.left)
		// The fix is only for an identifier without a type annotation.
		with_fix := left_kind == 'identifier' && !check.has_annotation
		if left_kind in ['array_pattern', 'identifier', 'object_pattern'] && check.has_annotation
			&& !options.enforce_for_declaration_with_type_annotation {
			continue
		}
		if right := check.right {
			// An access with an integer index to something that cannot be iterated is not an
			// array destructuring.
			if pd_is_member(right) && c.pd_is_integer_index(right) {
				object := unwrap_parens(node_field(right, 'object') or { continue })
				if node_kind(object) != 'super' {
					if object_type := c.node_type(object) {
						if !c.pd_is_any_or_iterable(object_type)! {
							if options.enforce_for_renamed_properties
								&& options.typed_object[check.node_type] {
								findings << Finding{
									stmt:       position_of(check.node)
									message_id: 'preferDestructuring'
									data:       {
										'type': 'object'
									}
								}
							}
							continue
						}
					}
				}
			}
		}
		// The core rule.
		right := check.right or { continue }
		if check.node_type == 'VariableDeclarator' && check.is_using {
			continue
		}
		if !pd_is_member(right) {
			continue
		}
		object := unwrap_parens(node_field(right, 'object') or { continue })
		property := member_property(right) or { continue }
		if node_kind(object) == 'super' || node_kind(property) == 'private_property_identifier' {
			continue
		}
		enabled := options.core[check.node_type]
		if c.pd_is_integer_index(right) {
			if enabled.array {
				findings << Finding{
					stmt:       position_of(check.node)
					message_id: 'preferDestructuring'
					data:       {
						'type': 'array'
					}
				}
			}
			continue
		}
		if !enabled.object {
			continue
		}
		computed := node_kind(right) == 'subscript_expression'
		left_name := if left_kind == 'identifier' { c.identifier_name(check.left) } else { '' }
		is_named := left_kind == 'identifier'
		// The property has the name of the variable: `foo = object.foo` or `foo = object['foo']`.
		same_name := is_named && ((computed && node_kind(property) == 'string'
			&& (c.literal_string_value(property) or { '\0' }) == left_name)
			|| (!computed && node_kind(property) == 'property_identifier'
				&& c.identifier_name(property) == left_name))
		if !options.core_enforce_for_renamed_properties && !same_name {
			continue
		}
		mut finding := Finding{
			stmt:       position_of(check.node)
			message_id: 'preferDestructuring'
			data:       {
				'type': 'object'
			}
		}
		// shouldFix: a declarator of an identifier with the name of the property it reads.
		if with_fix && check.node_type == 'VariableDeclarator' && !computed
			&& node_kind(property) == 'property_identifier'
			&& c.identifier_name(property) == left_name {
			if fix := c.pd_fix(check.node, object, c.identifier_name(property)) {
				finding = Finding{
					...finding
					has_fix: true
					fix:     fix
				}
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checks.len
	return findings
}

// pd_is_member: the node is a MemberExpression, not the ChainExpression of an optional chain.
fn pd_is_member(n C.TSNode) bool {
	return is_member(n) && !is_estree_chain_root(n)
}

// pd_is_integer_index ports isArrayIndexAccess: the property is a Literal whose value is an
// integer number.
fn (c &Checker) pd_is_integer_index(member C.TSNode) bool {
	if node_kind(member) != 'subscript_expression' {
		return false
	}
	property := member_property(member) or { return false }
	if node_kind(property) != 'number' {
		return false
	}
	text := c.text(property)
	if text.ends_with('n') {
		return false
	}
	shown := js_number_string(text) or { return false }
	value := js_atof64(shown) or { return false }
	return !math.is_nan(value) && !math.is_inf(value, 0) && value == math.floor(value)
}

// pd_is_any_or_iterable ports isTypeAnyOrIterableType: `any`, a type with `[Symbol.iterator]`,
// or a union of such.
fn (mut c Checker) pd_is_any_or_iterable(t TypeResponse) !bool {
	if t.flags & type_flag_any != 0 {
		return true
	}
	if t.flags & type_flag_union == 0 {
		return c.has_well_known_property(t, 'iterator')!
	}
	for part in c.members_of(t)! {
		if !c.pd_is_any_or_iterable(part)! {
			return false
		}
	}
	return true
}

// pd_fix ports fixIntoObjectDestructuring: `foo = object.foo` becomes `{foo} = object`, unless a
// comment would be lost.
fn (mut c Checker) pd_fix(declarator C.TSNode, object C.TSNode, name string) ?Fix {
	tokens := c.source_tokens(declarator)
	if tokens.comments_inside(node_start(declarator), node_end(declarator)).len > tokens.comments_inside(node_start(object),
		node_end(object)).len {
		return none
	}
	mut object_text := c.text(object)
	// getPrecedence(object) < the precedence of an assignment.
	if node_kind(object) == 'sequence_expression' || node_kind(object) in pd_unknown_precedence_kinds {
		object_text = '(${object_text})'
	}
	return fix_replace(declarator, '{${name}} = ${object_text}')
}
