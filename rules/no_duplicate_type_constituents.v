module rules

import json2
import strings
import time
import treesitter { children, has_child_kind, named_children, node_end, node_field, node_kind, node_parent, node_start, nodes_of_kinds, position_of }

// Port of the `no-duplicate-type-constituents` rule of typescript-eslint 8.62.0, with all its
// options and its fix.

const ndtc_messages = {
	'duplicate':   '{{type}} type constituent is duplicated with {{previous}}.'
	'unnecessary': 'Explicit undefined is unnecessary on an optional parameter.'
}

struct NdtcOptions {
	ignore_intersections bool
	ignore_unions        bool
}

fn ndtc_options(options []json2.Any) !NdtcOptions {
	o := option_object(no_duplicate_type_constituents, options, ['ignoreIntersections', 'ignoreUnions'])!
	return NdtcOptions{
		ignore_intersections: o.bool_value('ignoreIntersections')!
		ignore_unions:        o.bool_value('ignoreUnions')!
	}
}

// NdtcCheck is a TSUnionType or TSIntersectionType the rule checks (checkDuplicate): one that is
// not a constituent of another of its kind.
struct NdtcCheck {
	node C.TSNode
	kind string // 'union_type' or 'intersection_type'
	// forEachNodeType applies: the union annotates an optional parameter of a function.
	optional_parameter bool
}

// NdtcState holds what checkDuplicate remembers while it walks the constituents of a check.
struct NdtcState {
mut:
	unique []C.TSNode       // uniqueConstituents
	forms  []string         // the ESTree shape (ndtc_shape) of each unique constituent
	cached map[int]C.TSNode // cachedTypeMap: the first constituent of each type
}

fn (mut c Checker) lint_no_duplicate_type_constituents(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := ndtc_options(c.rule_options(no_duplicate_type_constituents))!
	mut kinds := []string{}
	if !o.ignore_intersections {
		kinds << 'intersection_type'
	}
	if !o.ignore_unions {
		kinds << 'union_type'
	}
	if kinds.len == 0 {
		return []Finding{}
	}
	mut checks := []NdtcCheck{}
	mut spans := []Span{}
	for node in c.nodes_of_kinds(root, kinds, []string{}) {
		kind := node_kind(node)
		parent := node_parent(node) or { continue }
		// tree-sitter nests `A | B | C` as `(A | B) | C`: the inner one is not an ESTree node.
		if node_kind(parent) == kind {
			continue
		}
		estree_parent_type := type_parent(node) or { continue }
		if node_kind(estree_parent_type) == kind {
			continue
		}
		checks << NdtcCheck{
			node:               node
			kind:               kind
			optional_parameter: kind == 'union_type' && ndtc_annotates_optional_parameter(estree_parent_type)
		}
		c.ndtc_spans(node, kind, mut spans)
	}
	c.resolve_spans(spans, abs_path, mut stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for check in checks {
		mut state := NdtcState{}
		for member in type_members(check.node) {
			c.ndtc_check_recursively(check, member, mut state, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checks.len
	return findings
}

// ndtc_spans requests the type of every constituent the check may look at.
fn (c &Checker) ndtc_spans(node C.TSNode, kind string, mut spans []Span) {
	for member in type_members(node) {
		spans << c.type_node_span(member)
		if node_kind(member) == kind {
			c.ndtc_spans(member, kind, mut spans)
		}
	}
}

// ndtc_annotates_optional_parameter: the ESTree parent of the union is the TSTypeAnnotation of an
// optional Identifier parameter of a function (isFunctionOrFunctionType). A parameter with
// modifiers is a TSParameterProperty, and one with a default value an AssignmentPattern.
fn ndtc_annotates_optional_parameter(type_parent C.TSNode) bool {
	if node_kind(type_parent) != 'type_annotation' {
		return false
	}
	parameter := node_parent(type_parent) or { return false }
	if node_kind(parameter) != 'optional_parameter' {
		return false
	}
	pattern := node_field(parameter, 'pattern') or { return false }
	if node_kind(pattern) != 'identifier' {
		return false
	}
	if _ := node_field(parameter, 'value') {
		return false
	}
	return !has_child_kind(parameter, 'accessibility_modifier')
		&& !has_child_kind(parameter, 'override_modifier') && !has_child_kind(parameter, 'readonly')
}

// ndtc_check_recursively ports checkDuplicateRecursively.
fn (mut c Checker) ndtc_check_recursively(check NdtcCheck, constituent C.TSNode, mut state NdtcState, mut findings []Finding) ! {
	form := c.ndtc_shape(constituent)
	// isSameAstNode first, then the type.
	for i, previous in state.unique {
		if state.forms[i] == form {
			findings << c.ndtc_duplicate(check, constituent, previous)!
			return
		}
	}
	t := c.node_type(constituent) or { return }
	if is_error_type(t) {
		return
	}
	if t.id in state.cached {
		findings << c.ndtc_duplicate(check, constituent, state.cached[t.id])!
		return
	}
	// forEachNodeType: tsutils.isTypeFlagSet, on the type's own flags.
	if check.optional_parameter && t.flags & type_flag_undefined != 0 {
		findings << c.with_fixes(Finding{
			stmt:       position_of(constituent)
			message_id: 'unnecessary'
		}, ndtc_removal(constituent))!
	}
	state.cached[t.id] = constituent
	state.unique << constituent
	state.forms << form
	if node_kind(constituent) == check.kind {
		for member in type_members(constituent) {
			c.ndtc_check_recursively(check, member, mut state, mut findings)!
		}
	}
}

fn (c &Checker) ndtc_duplicate(check NdtcCheck, constituent C.TSNode, previous C.TSNode) !Finding {
	return c.with_fixes(Finding{
		stmt:       position_of(constituent)
		message_id: 'duplicate'
		data:       {
			'type':     if check.kind == 'union_type' { 'Union' } else { 'Intersection' }
			'previous': c.text(previous)
		}
	}, ndtc_removal(constituent))!
}

// ndtc_removal ports the fixer of `report`: it removes the constituent, the parentheses around it
// (the tokens between it and the operator, and as many on its other side) and the `|` or `&` before
// it or, for the first constituent of its union or intersection, the one after it. ESLint merges
// these removals into one fix that keeps the text between them.
fn ndtc_removal(constituent C.TSNode) []Fix {
	mut fixes := [fix_remove(constituent)]
	mut outer := constituent
	for {
		parent := node_parent(outer) or { break }
		if node_kind(parent) != 'parenthesized_type' {
			break
		}
		for token in children(parent) {
			if node_kind(token) in ['(', ')'] {
				fixes << fix_remove(token)
			}
		}
		outer = parent
	}
	// The operators of the tree-sitter node the constituent is an operand of: `A | B`, or `| A`
	// with a leading one.
	owner := node_parent(outer) or { return []Fix{} }
	operators := children(owner).filter(node_kind(it) in ['|', '&'])
	before := operators.filter(node_end(it) <= node_start(outer))
	if before.len > 0 {
		fixes << fix_remove(before.last())
		return fixes
	}
	after := operators.filter(node_start(it) >= node_end(outer))
	if after.len == 0 {
		// typescript-eslint throws without an operator.
		return []Fix{}
	}
	fixes << fix_remove(after[0])
	return fixes
}

// ndtc_shape is a text that two type nodes share when they are the same ESTree node apart from
// their positions (isSameAstNode): kinds and tokens, without comments, parentheses or the `,`
// and `;` separators, with unions and intersections flattened like ESTree's.
fn (c &Checker) ndtc_shape(n C.TSNode) string {
	mut sb := strings.new_builder(64)
	c.ndtc_write_shape(n, mut sb)
	return sb.str()
}

fn (c &Checker) ndtc_write_shape(n C.TSNode, mut sb strings.Builder) {
	kind := node_kind(n)
	match kind {
		'comment', ',', ';' {
			return
		}
		'parenthesized_type' {
			inner := first_named(n) or { return }
			c.ndtc_write_shape(inner, mut sb)
			return
		}
		'union_type', 'intersection_type' {
			sb.write_string(kind)
			sb.write_u8(`[`)
			for member in type_members(n) {
				c.ndtc_write_shape(member, mut sb)
				sb.write_u8(`,`)
			}
			sb.write_u8(`]`)
			return
		}
		else {}
	}
	if C.ts_node_child_count(n) == 0 {
		sb.write_string(kind)
		sb.write_u8(`:`)
		sb.write_string(c.text(n))
		sb.write_u8(0)
		return
	}
	sb.write_string(kind)
	sb.write_u8(`(`)
	for child in children(n) {
		c.ndtc_write_shape(child, mut sb)
	}
	sb.write_u8(`)`)
}
