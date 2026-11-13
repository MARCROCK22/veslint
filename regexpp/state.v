module regexpp

// RegExpParserState ported from regexpp 4.12.2: the validator calls these methods when `build` is set. Every
// `throw new Error("UnknownError")` of regexpp returns UnknownError.

struct ParserState {
mut:
	nodes      []Node
	cur        int = -1
	expr_buf   map[int]int
	backrefs   []int
	cap_groups []int
	flags_node int = -1
}

fn unknown() IError {
	return UnknownError{}
}

fn (mut v Validator) add_node(n Node) int {
	v.st.nodes << n
	return v.st.nodes.len - 1
}

@[inline]
fn (v &Validator) kind_of(i int) NodeKind {
	return v.st.nodes[i].kind
}

fn (mut v Validator) st_flags(start int, end int, f FlagSet) {
	v.st.flags_node = v.add_node(Node{
		kind:         .flags
		start:        start
		end:          end
		global:       f.global
		ignore_case:  f.ignore_case
		multiline:    f.multiline
		unicode:      f.unicode
		sticky:       f.sticky
		dot_all:      f.dot_all
		has_indices:  f.has_indices
		unicode_sets: f.unicode_sets
	})
}

fn (mut v Validator) st_pattern_enter(start int) {
	v.st.cur = v.add_node(Node{
		kind:  .pattern
		start: start
		end:   start
	})
	v.st.backrefs.clear()
	v.st.cap_groups.clear()
}

fn (mut v Validator) st_pattern_leave(end int) ! {
	if v.st.cur < 0 {
		return unknown()
	}
	v.st.nodes[v.st.cur].end = end
	for reference in v.st.backrefs {
		r := v.st.nodes[reference]
		mut groups := []int{}
		if r.ref_is_name {
			for g in v.st.cap_groups {
				gn := v.st.nodes[g]
				if gn.has_name && gn.name == r.ref_name {
					groups << g
				}
			}
		} else {
			if r.ref_num - 1 < 0 || r.ref_num - 1 >= v.st.cap_groups.len {
				// regexpp would throw a TypeError here (`undefined.references`).
				return unknown()
			}
			groups << v.st.cap_groups[r.ref_num - 1]
		}
		v.st.nodes[reference].ambiguous = groups.len != 1
		v.st.nodes[reference].resolved = groups
		for g in groups {
			v.st.nodes[g].references << reference
		}
	}
}

fn (mut v Validator) st_alternative_enter(start int) ! {
	parent := v.st.cur
	if parent < 0 {
		return unknown()
	}
	pk := v.kind_of(parent)
	if pk != .assertion && pk != .capturing_group && pk != .group && pk != .pattern {
		return unknown()
	}
	n := v.add_node(Node{
		kind:   .alternative
		parent: parent
		start:  start
		end:    start
	})
	v.st.nodes[parent].alternatives << n
	v.st.cur = n
}

fn (mut v Validator) st_alternative_leave(end int) ! {
	node := v.st.cur
	if node < 0 || v.kind_of(node) != .alternative {
		return unknown()
	}
	v.st.nodes[node].end = end
	v.st.cur = v.st.nodes[node].parent
}

// st_leave_container is onGroupLeave, onCapturingGroupLeave, onLookaroundAssertionLeave, onModifiersLeave,
// onClassStringDisjunctionLeave and onStringAlternativeLeave.
fn (mut v Validator) st_leave_container(end int, kind NodeKind) ! {
	node := v.st.cur
	if node < 0 || v.kind_of(node) != kind {
		return unknown()
	}
	parent := v.st.nodes[node].parent
	match kind {
		.group, .capturing_group, .assertion {
			if v.kind_of(parent) != .alternative {
				return unknown()
			}
		}
		.modifiers {
			if v.kind_of(parent) != .group {
				return unknown()
			}
		}
		.class_string_disjunction {
			if v.kind_of(parent) != .character_class {
				return unknown()
			}
		}
		else {}
	}
	v.st.nodes[node].end = end
	v.st.cur = parent
}

fn (mut v Validator) parent_alternative() !int {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .alternative {
		return unknown()
	}
	return parent
}

fn (mut v Validator) st_group_enter(start int) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:   .group
		parent: parent
		start:  start
		end:    start
	})
	v.st.cur = n
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_modifiers_enter(start int) ! {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .group {
		return unknown()
	}
	n := v.add_node(Node{
		kind:   .modifiers
		parent: parent
		start:  start
		end:    start
	})
	v.st.cur = n
	v.st.nodes[parent].modifiers = n
}

fn (mut v Validator) st_modifier_flags(start int, end int, f ModifierFlagSet, add bool) ! {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .modifiers {
		return unknown()
	}
	n := v.add_node(Node{
		kind:        .modifier_flags
		parent:      parent
		start:       start
		end:         end
		ignore_case: f.ignore_case
		multiline:   f.multiline
		dot_all:     f.dot_all
	})
	if add {
		v.st.nodes[parent].add = n
	} else {
		v.st.nodes[parent].remove = n
	}
}

fn (mut v Validator) st_capturing_group_enter(start int, name string, has_name bool) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:     .capturing_group
		parent:   parent
		start:    start
		end:      start
		name:     name
		has_name: has_name
	})
	v.st.cur = n
	v.st.nodes[parent].elements << n
	v.st.cap_groups << n
}

fn (mut v Validator) st_quantifier(end int, min f64, max f64, greedy bool) ! {
	parent := v.parent_alternative()!
	if v.st.nodes[parent].elements.len == 0 {
		return unknown()
	}
	element := v.st.nodes[parent].elements.pop()
	ek := v.kind_of(element)
	if ek == .quantifier || (ek == .assertion && v.st.nodes[element].assertion_kind != .lookahead) {
		return unknown()
	}
	n := v.add_node(Node{
		kind:    .quantifier
		parent:  parent
		start:   v.st.nodes[element].start
		end:     end
		min:     min
		max:     max
		greedy:  greedy
		element: element
	})
	v.st.nodes[parent].elements << n
	v.st.nodes[element].parent = n
}

fn (mut v Validator) st_lookaround_enter(start int, kind AssertionKind, negate bool) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:           .assertion
		parent:         parent
		start:          start
		end:            start
		assertion_kind: kind
		negate:         negate
	})
	v.st.cur = n
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_edge_assertion(start int, end int, kind AssertionKind) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:           .assertion
		parent:         parent
		start:          start
		end:            end
		assertion_kind: kind
	})
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_word_boundary_assertion(start int, end int, negate bool) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:           .assertion
		parent:         parent
		start:          start
		end:            end
		assertion_kind: .word
		negate:         negate
	})
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_any_character_set(start int, end int) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:     .character_set
		parent:   parent
		start:    start
		end:      end
		set_kind: .any
	})
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) parent_alternative_or_class() !int {
	parent := v.st.cur
	if parent < 0 {
		return unknown()
	}
	pk := v.kind_of(parent)
	if pk != .alternative && pk != .character_class {
		return unknown()
	}
	return parent
}

fn (mut v Validator) st_escape_character_set(start int, end int, kind CharacterSetKind, negate bool) ! {
	parent := v.parent_alternative_or_class()!
	n := v.add_node(Node{
		kind:     .character_set
		parent:   parent
		start:    start
		end:      end
		set_kind: kind
		negate:   negate
	})
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_unicode_property_character_set(start int, end int, r PropertyResult, negate bool) ! {
	parent := v.parent_alternative_or_class()!
	if r.strings {
		p := v.st.nodes[parent]
		if (p.kind == .character_class && !p.unicode_sets) || negate || r.has_value {
			return unknown()
		}
	}
	n := v.add_node(Node{
		kind:      .character_set
		parent:    parent
		start:     start
		end:       end
		set_kind:  .property
		key:       r.key
		value_str: r.value
		has_value: r.has_value
		strings:   r.strings
		negate:    negate
	})
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_character(start int, end int, value int) ! {
	parent := v.st.cur
	if parent < 0 {
		return unknown()
	}
	pk := v.kind_of(parent)
	if pk != .alternative && pk != .character_class && pk != .string_alternative {
		return unknown()
	}
	n := v.add_node(Node{
		kind:   .character
		parent: parent
		start:  start
		end:    end
		value:  value
	})
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_backreference(start int, end int, ref_num int, ref_name string, ref_is_name bool) ! {
	parent := v.parent_alternative()!
	n := v.add_node(Node{
		kind:        .backreference
		parent:      parent
		start:       start
		end:         end
		ref_num:     ref_num
		ref_name:    ref_name
		ref_is_name: ref_is_name
	})
	v.st.nodes[parent].elements << n
	v.st.backrefs << n
}

fn (mut v Validator) st_character_class_enter(start int, negate bool, unicode_sets bool) ! {
	parent := v.st.cur
	if parent < 0 {
		return unknown()
	}
	p := v.st.nodes[parent]
	if p.kind != .alternative && !(p.kind == .character_class && p.unicode_sets && unicode_sets) {
		return unknown()
	}
	n := v.add_node(Node{
		kind:         .character_class
		parent:       parent
		start:        start
		end:          start
		unicode_sets: unicode_sets
		negate:       negate
	})
	v.st.cur = n
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_character_class_leave(end int) ! {
	node := v.st.cur
	if node < 0 || v.kind_of(node) != .character_class {
		return unknown()
	}
	parent := v.st.nodes[node].parent
	pk := v.kind_of(parent)
	if pk != .alternative && pk != .character_class {
		return unknown()
	}
	v.st.nodes[node].end = end
	v.st.cur = parent
	expression := v.st.expr_buf[node] or { return }
	if v.st.nodes[node].elements.len > 0 {
		return unknown()
	}
	v.st.expr_buf.delete(node)
	nn := v.add_node(Node{
		kind:       .expression_character_class
		parent:     parent
		start:      v.st.nodes[node].start
		end:        v.st.nodes[node].end
		negate:     v.st.nodes[node].negate
		expression: expression
	})
	v.st.nodes[expression].parent = nn
	if v.st.nodes[parent].elements.len == 0 || v.st.nodes[parent].elements.pop() != node {
		return unknown()
	}
	v.st.nodes[parent].elements << nn
}

fn (mut v Validator) st_character_class_range(start int, end int) ! {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .character_class {
		return unknown()
	}
	if v.st.nodes[parent].elements.len == 0 {
		return unknown()
	}
	max := v.st.nodes[parent].elements.pop()
	if v.kind_of(max) != .character {
		return unknown()
	}
	if !v.st.nodes[parent].unicode_sets {
		if v.st.nodes[parent].elements.len == 0 {
			return unknown()
		}
		hyphen := v.st.nodes[parent].elements.pop()
		if v.kind_of(hyphen) != .character || v.st.nodes[hyphen].value != hyphen_minus {
			return unknown()
		}
	}
	if v.st.nodes[parent].elements.len == 0 {
		return unknown()
	}
	min := v.st.nodes[parent].elements.pop()
	if v.kind_of(min) != .character {
		return unknown()
	}
	n := v.add_node(Node{
		kind:     .character_class_range
		parent:   parent
		start:    start
		end:      end
		min_char: min
		max_char: max
	})
	v.st.nodes[min].parent = n
	v.st.nodes[max].parent = n
	v.st.nodes[parent].elements << n
}

fn is_class_set_operand(k NodeKind) bool {
	return k == .character || k == .character_set || k == .character_class
		|| k == .expression_character_class || k == .class_string_disjunction
}

// st_class_set_operation is onClassIntersection (intersection) and onClassSubtraction.
fn (mut v Validator) st_class_set_operation(start int, end int, intersection bool) ! {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .character_class || !v.st.nodes[parent].unicode_sets {
		return unknown()
	}
	mut right := -1
	if v.st.nodes[parent].elements.len > 0 {
		right = v.st.nodes[parent].elements.pop()
	}
	mut left := v.st.expr_buf[parent] or { -1 }
	if left < 0 && v.st.nodes[parent].elements.len > 0 {
		left = v.st.nodes[parent].elements.pop()
	}
	if left < 0 || right < 0 {
		return unknown()
	}
	lk := v.kind_of(left)
	own, other := if intersection {
		NodeKind.class_intersection, NodeKind.class_subtraction
	} else {
		NodeKind.class_subtraction, NodeKind.class_intersection
	}
	if lk == other || (lk != own && !is_class_set_operand(lk)) || !is_class_set_operand(v.kind_of(right)) {
		return unknown()
	}
	n := v.add_node(Node{
		kind:   own
		parent: parent
		start:  start
		end:    end
		left:   left
		right:  right
	})
	v.st.nodes[left].parent = n
	v.st.nodes[right].parent = n
	v.st.expr_buf[parent] = n
}

fn (mut v Validator) st_class_string_disjunction_enter(start int) ! {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .character_class || !v.st.nodes[parent].unicode_sets {
		return unknown()
	}
	n := v.add_node(Node{
		kind:   .class_string_disjunction
		parent: parent
		start:  start
		end:    start
	})
	v.st.cur = n
	v.st.nodes[parent].elements << n
}

fn (mut v Validator) st_string_alternative_enter(start int) ! {
	parent := v.st.cur
	if parent < 0 || v.kind_of(parent) != .class_string_disjunction {
		return unknown()
	}
	n := v.add_node(Node{
		kind:   .string_alternative
		parent: parent
		start:  start
		end:    start
	})
	v.st.cur = n
	v.st.nodes[parent].alternatives << n
}
