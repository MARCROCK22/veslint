module regexpp

import math

// The regexpp AST as an arena. Children are indexes into `Ast.nodes`; -1 means null.

pub enum NodeKind {
	pattern
	alternative
	group
	capturing_group
	quantifier
	character_class
	character_class_range
	class_intersection
	class_subtraction
	class_string_disjunction
	string_alternative
	expression_character_class
	assertion
	character
	character_set
	backreference
	flags
	regexp_literal
	modifiers
	modifier_flags
}

// type_name gives regexpp's `type` string.
pub fn (k NodeKind) type_name() string {
	return match k {
		.pattern { 'Pattern' }
		.alternative { 'Alternative' }
		.group { 'Group' }
		.capturing_group { 'CapturingGroup' }
		.quantifier { 'Quantifier' }
		.character_class { 'CharacterClass' }
		.character_class_range { 'CharacterClassRange' }
		.class_intersection { 'ClassIntersection' }
		.class_subtraction { 'ClassSubtraction' }
		.class_string_disjunction { 'ClassStringDisjunction' }
		.string_alternative { 'StringAlternative' }
		.expression_character_class { 'ExpressionCharacterClass' }
		.assertion { 'Assertion' }
		.character { 'Character' }
		.character_set { 'CharacterSet' }
		.backreference { 'Backreference' }
		.flags { 'Flags' }
		.regexp_literal { 'RegExpLiteral' }
		.modifiers { 'Modifiers' }
		.modifier_flags { 'ModifierFlags' }
	}
}

pub enum AssertionKind {
	start
	end
	word
	lookahead
	lookbehind
}

pub fn (k AssertionKind) str() string {
	return match k {
		.start { 'start' }
		.end { 'end' }
		.word { 'word' }
		.lookahead { 'lookahead' }
		.lookbehind { 'lookbehind' }
	}
}

pub enum CharacterSetKind {
	any
	digit
	space
	word
	property
}

pub fn (k CharacterSetKind) str() string {
	return match k {
		.any { 'any' }
		.digit { 'digit' }
		.space { 'space' }
		.word { 'word' }
		.property { 'property' }
	}
}

// Node is one regexpp node. Which fields are meaningful depends on `kind` (see the comments, which name the regexpp
// property each field stands for).
pub struct Node {
pub mut:
	kind   NodeKind
	parent int = -1
	start  int
	end    int
	// Pattern, Group, CapturingGroup, lookaround Assertion, ClassStringDisjunction: `alternatives`.
	alternatives []int
	// Alternative, CharacterClass, StringAlternative: `elements`.
	elements []int
	// Quantifier: `element`.
	element int = -1
	// Group: `modifiers` (-1 = null).
	modifiers int = -1
	// Modifiers: `add` and `remove` (ModifierFlags, -1 = null).
	add    int = -1
	remove int = -1
	// ClassIntersection, ClassSubtraction: `left`, `right`.
	left  int = -1
	right int = -1
	// ExpressionCharacterClass: `expression`.
	expression int = -1
	// CharacterClassRange: `min`, `max` (Character nodes).
	min_char int = -1
	max_char int = -1
	// RegExpLiteral: `pattern`, `flags`.
	pattern int = -1
	flags   int = -1
	// Quantifier: `min`, `max` (max may be math.inf(1); both are JS numbers), `greedy`.
	min    f64
	max    f64
	greedy bool
	// CapturingGroup: `name` (has_name false = null), `references` (Backreference nodes).
	name       string
	has_name   bool
	references []int
	// Assertion (word, lookahead, lookbehind), CharacterSet (all but any), CharacterClass,
	// ExpressionCharacterClass: `negate`.
	negate bool
	// CharacterClass, Flags: `unicodeSets`.
	unicode_sets bool
	// Character: `value` (a code point, or a UTF-16 unit outside unicode mode).
	value int
	// Assertion: `kind`.
	assertion_kind AssertionKind
	// CharacterSet: `kind`; for kind property also `key`, `value` (has_value false = null) and `strings`.
	set_kind  CharacterSetKind
	key       string
	value_str string
	has_value bool
	strings   bool
	// Backreference: `ref` (ref_name when ref_is_name, else ref_num), `ambiguous`, `resolved` (one CapturingGroup
	// when not ambiguous, else all of them).
	ref_num     int
	ref_name    string
	ref_is_name bool
	ambiguous   bool
	resolved    []int
	// Flags: the eight flags. ModifierFlags uses ignore_case, multiline and dot_all.
	global      bool
	ignore_case bool
	multiline   bool
	unicode     bool
	sticky      bool
	dot_all     bool
	has_indices bool
}

pub struct Ast {
pub:
	source []u16
pub mut:
	nodes []Node
	root  int = -1
}

// raw16 returns the node's `raw` as UTF-16 units (a RegExpLiteral's raw is the whole source, like regexpp).
pub fn (a &Ast) raw16(i int) []u16 {
	n := a.nodes[i]
	if n.kind == .regexp_literal {
		return a.source
	}
	return a.source[n.start..n.end]
}

// raw returns the node's `raw` as a string (WTF-8 for lone surrogates).
pub fn (a &Ast) raw(i int) string {
	return utf16_to_wtf8(a.raw16(i))
}

pub fn quantifier_is_infinite(max f64) bool {
	return math.is_inf(max, 1)
}

pub struct VisitEvent {
pub:
	enter bool
	node  int
}

// walk calls cb for every node, with enter before the children and leave after them, in the order of regexpp's
// RegExpVisitor (visitRegExpAST) onXEnter/onXLeave calls.
pub fn (a &Ast) walk(cb fn (VisitEvent)) {
	a.walk_node(a.root, cb)
}

// visit_events returns the walk as a list.
pub fn (a &Ast) visit_events() []VisitEvent {
	mut out := []VisitEvent{cap: a.nodes.len * 2}
	a.collect(a.root, mut out)
	return out
}

fn (a &Ast) collect(i int, mut out []VisitEvent) {
	out << VisitEvent{true, i}
	for c in a.children(i) {
		a.collect(c, mut out)
	}
	out << VisitEvent{false, i}
}

fn (a &Ast) walk_node(i int, cb fn (VisitEvent)) {
	cb(VisitEvent{true, i})
	for c in a.children(i) {
		a.walk_node(c, cb)
	}
	cb(VisitEvent{false, i})
}

// children lists the node's children in visiting order.
pub fn (a &Ast) children(i int) []int {
	n := a.nodes[i]
	return match n.kind {
		.pattern, .capturing_group, .class_string_disjunction {
			n.alternatives
		}
		.alternative, .character_class, .string_alternative {
			n.elements
		}
		.assertion {
			if n.assertion_kind == .lookahead || n.assertion_kind == .lookbehind {
				n.alternatives
			} else {
				[]int{}
			}
		}
		.group {
			if n.modifiers >= 0 {
				mut l := [n.modifiers]
				l << n.alternatives
				l
			} else {
				n.alternatives
			}
		}
		.modifiers {
			mut l := []int{}
			if n.add >= 0 {
				l << n.add
			}
			if n.remove >= 0 {
				l << n.remove
			}
			l
		}
		.quantifier {
			[n.element]
		}
		.character_class_range {
			[n.min_char, n.max_char]
		}
		.class_intersection, .class_subtraction {
			[n.left, n.right]
		}
		.expression_character_class {
			[n.expression]
		}
		.regexp_literal {
			[n.pattern, n.flags]
		}
		.character, .character_set, .backreference, .flags, .modifier_flags {
			[]int{}
		}
	}
}

// compact keeps only the nodes reachable from the root (the "parse twice" leaves the first pass behind), renumbered
// in visiting order.
fn (mut a Ast) compact() {
	mut order := []int{cap: a.nodes.len}
	mut stack := [a.root]
	for stack.len > 0 {
		i := stack.pop()
		order << i
		ch := a.children(i)
		for j := ch.len - 1; j >= 0; j-- {
			stack << ch[j]
		}
	}
	mut remap := []int{len: a.nodes.len, init: -1}
	for k, i in order {
		remap[i] = k
	}
	mut nodes := []Node{cap: order.len}
	for i in order {
		mut n := a.nodes[i]
		m := fn [remap] (x int) int {
			return if x < 0 { x } else { remap[x] }
		}
		n.parent = m(n.parent)
		n.alternatives = n.alternatives.map(m(it))
		n.elements = n.elements.map(m(it))
		n.element = m(n.element)
		n.modifiers = m(n.modifiers)
		n.add = m(n.add)
		n.remove = m(n.remove)
		n.left = m(n.left)
		n.right = m(n.right)
		n.expression = m(n.expression)
		n.min_char = m(n.min_char)
		n.max_char = m(n.max_char)
		n.pattern = m(n.pattern)
		n.flags = m(n.flags)
		n.references = n.references.map(m(it))
		n.resolved = n.resolved.map(m(it))
		nodes << n
	}
	a.nodes = nodes
	a.root = 0
}
