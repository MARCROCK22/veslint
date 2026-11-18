module svelte_compiler

// The AST the Svelte 5.56.0 compiler analyzes (`compile()` after `parse` and
// remove_typescript_nodes): the template nodes, the JavaScript of the scripts and template
// expressions (acorn's ESTree, TypeScript removed), and the nodes of the <style> (its own CSS
// parser), in one arena. Nodes refer to each other by index (-1: null). Properties are kept as
// a list of (key, value) as the JavaScript objects have them; the walker (walk.v) visits the
// children in the order of the JavaScript objects' keys, which decides the order of references
// and warnings. Positions are byte offsets of the source; `no_pos` is an undefined position
// (nodes the compiler makes up, like `b.id(name)`).

pub const no_pos = -1_000_000_000

pub enum Key as u8 {
	// ESTree
	alternate
	argument
	arguments
	block
	body
	callee
	cases
	consequent
	declaration
	declarations
	discriminant
	elements
	exported
	expression
	expressions
	finalizer
	handler
	id
	imported
	init
	key
	label
	left
	local
	meta
	object
	options
	param
	params
	properties
	property
	quasi
	quasis
	right
	source
	specifiers
	super_class
	tag
	test
	update
	value
	// scalars of ESTree nodes
	name
	operator
	kind
	computed
	shorthand
	method
	static_
	prefix
	optional
	async
	generator
	delegate
	raw
	cooked
	tail
	declare
	import_kind
	export_kind
	abstract_
	accessor
	regex
	bigint
	// template
	fragment
	nodes
	attributes
	elseif
	context
	index
	fallback
	pending
	then
	catch_
	error
	parameters
	identifiers
	content
	modifiers
	intro
	outro
	data
	transparent
	// CSS
	children
	prelude
	selectors
	args
	combinator
	matcher
	flags
	property_name
}

pub enum PK as u8 {
	null_
	node
	list
	str
	boolean
	num
	strs
}

// P is a property: a node (`idx`, -1 for null), a list of nodes, a string, a boolean, a number
// or a list of strings (modifiers).
pub struct P {
pub mut:
	key  Key
	kind PK
	idx  int = -1
	list []int
	s    string
	b    bool
	n    f64
	strs []string
}

pub struct Node {
pub mut:
	typ   string
	start int = no_pos
	end   int = no_pos
	props []P
	// leading / trailing: the comments acorn.js attaches (indexes of Tree.comments).
	leading  []int
	trailing []int
}

pub struct Comment {
pub:
	block bool
	start int
	end   int
	value string
}

@[heap]
pub struct Tree {
pub mut:
	nodes    []Node
	comments []Comment
}

pub fn (mut t Tree) add(n Node) int {
	t.nodes << n
	return t.nodes.len - 1
}

pub fn (mut t Tree) new_node(typ string, start int, end int) int {
	t.nodes << Node{
		typ:   typ
		start: start
		end:   end
	}
	return t.nodes.len - 1
}

@[inline]
pub fn (t &Tree) typ(i int) string {
	if i < 0 {
		return ''
	}
	return t.nodes[i].typ
}

pub fn (t &Tree) prop(i int, k Key) ?P {
	if i < 0 {
		return none
	}
	for p in t.nodes[i].props {
		if p.key == k {
			return p
		}
	}
	return none
}

pub fn (t &Tree) has(i int, k Key) bool {
	t.prop(i, k) or { return false }
	return true
}

// get is the node of the property (-1: absent or null).
pub fn (t &Tree) get(i int, k Key) int {
	p := t.prop(i, k) or { return -1 }
	return if p.kind == .node { p.idx } else { -1 }
}

pub fn (t &Tree) list(i int, k Key) []int {
	p := t.prop(i, k) or { return [] }
	return if p.kind == .list { p.list } else { [] }
}

pub fn (t &Tree) text(i int, k Key) string {
	p := t.prop(i, k) or { return '' }
	return if p.kind == .str { p.s } else { '' }
}

pub fn (t &Tree) flag(i int, k Key) bool {
	p := t.prop(i, k) or { return false }
	return p.kind == .boolean && p.b
}

pub fn (t &Tree) strs(i int, k Key) []string {
	p := t.prop(i, k) or { return [] }
	return p.strs
}

// name is the `name` of the node (Identifier, PrivateIdentifier, elements, attributes…).
pub fn (t &Tree) name(i int) string {
	return t.text(i, .name)
}

pub fn (mut t Tree) set(i int, p P) {
	for k, q in t.nodes[i].props {
		if q.key == p.key {
			t.nodes[i].props[k] = p
			return
		}
	}
	t.nodes[i].props << p
}

pub fn (mut t Tree) set_node(i int, k Key, v int) {
	t.set(i, P{
		key:  k
		kind: if v < 0 { PK.null_ } else { PK.node }
		idx:  v
	})
}

pub fn (mut t Tree) set_list(i int, k Key, v []int) {
	t.set(i, P{
		key:  k
		kind: .list
		list: v
	})
}

pub fn (mut t Tree) set_str(i int, k Key, v string) {
	t.set(i, P{
		key:  k
		kind: .str
		s:    v
	})
}

pub fn (mut t Tree) set_flag(i int, k Key, v bool) {
	t.set(i, P{
		key:  k
		kind: .boolean
		b:    v
	})
}

pub fn (mut t Tree) set_null(i int, k Key) {
	t.set(i, P{
		key:  k
		kind: .null_
	})
}

// id makes a b.id(name): an Identifier without position.
pub fn (mut t Tree) id(name string) int {
	i := t.new_node('Identifier', no_pos, no_pos)
	t.set_str(i, .name, name)
	return i
}

// LitKind is the kind of a Literal's value.
pub enum LitKind as u8 {
	string
	number
	boolean
	null_
	regexp
	bigint
}

pub fn (t &Tree) lit_kind(i int) LitKind {
	p := t.prop(i, .value) or { return .null_ }
	if t.has(i, .regex) {
		return .regexp
	}
	if t.has(i, .bigint) {
		return .bigint
	}
	return match p.kind {
		.str { LitKind.string }
		.num { LitKind.number }
		.boolean { LitKind.boolean }
		else { LitKind.null_ }
	}
}

pub fn (t &Tree) lit_num(i int) f64 {
	p := t.prop(i, .value) or { return 0 }
	return p.n
}

// Diag is a warning or an error: its code and message (with the documentation link).
pub struct Diag {
pub:
	code    string
	message string
}
