module estree

// An ESTree view of a TypeScript file, identical to what @typescript-eslint/typescript-estree
// 8.62.0 (the parser of typescript-eslint) produces for it, converted from veslint's tree-sitter
// tree. The nodes live in an arena (EsTree.nodes) and refer to each other by index; -1 is no node.

// type_name is the ESTree name of the type (`Identifier`, `TSAsExpression`…).
pub fn (t NodeType) type_name() string {
	return node_type_names[int(t)]
}

// key_name is the ESTree name of the property (`typeAnnotation`, `in`…).
pub fn (k Key) key_name() string {
	return key_names[int(k)]
}

// ValueKind is the kind of the value of a property, as JavaScript sees it.
pub enum ValueKind as u8 {
	null
	bool
	number   // Prop.num
	string   // Prop.str (WTF-8: a lone UTF-16 surrogate is kept as its 3-byte encoding)
	node     // Prop.idx: index in EsTree.nodes
	list     // Prop.idx: index in EsTree.lists, whose items are node indexes or -1 (a hole)
	regex    // Literal.regex: Prop.str is the pattern, Prop.str2 the flags
	template // TemplateElement.value: Prop.str is `cooked` (null when Prop.b), Prop.str2 `raw`
	bigint   // Literal.value of a BigInt literal: Prop.str is its decimal digits (with `-`)
	regexp   // Literal.value of a regular expression V8 accepts: a RegExp object
}

// Prop is one own enumerable property of a node, other than `type`, `range`, `loc` and
// `parent`. A property whose value is `undefined` is not stored.
pub struct Prop {
pub:
	key  Key
	kind ValueKind
	b    bool
	num  f64
	idx  int
	str  string
	str2 string
}

// EsNode is an ESTree node. `start` and `end` are its `range` in bytes of the source (the end of
// its last token). `ts` is the tree-sitter node it was converted from, when `has_ts` (for a node
// typescript-estree makes up, like a ChainExpression or the TSTypeAnnotation of a type predicate,
// the node it is made from; a JSXText has none). `parent` is -1 for the Program.
pub struct EsNode {
pub mut:
	typ    NodeType
	start  int
	end    int
	parent int = -1
	ts     C.TSNode
	has_ts bool
	props  []Prop
}

pub struct EsTree {
pub mut:
	nodes []EsNode
	lists [][]int
	root  int
	// src is the text the tree was converted from; line_starts are the byte offsets where its
	// lines start, and line_units the UTF-16 offsets of the same places (see positions.v).
	src         string
	line_starts []int
	line_units  []int
}

// Value is the value of a property as a sum type (see EsTree.get).
pub type Value = Undefined
	| Null
	| bool
	| f64
	| string
	| NodeRef
	| NodeList
	| RegexInfo
	| TemplateValue
	| BigIntValue
	| RegExpValue

// Undefined is the value of a property the node does not have (or has as `undefined`).
pub struct Undefined {}

pub struct Null {}

pub struct NodeRef {
pub:
	index int
}

// NodeList is an array of nodes; -1 is a hole (`null`, as in `[a, , b]`).
pub struct NodeList {
pub:
	items []int
}

// RegexInfo is `Literal.regex`.
pub struct RegexInfo {
pub:
	pattern string
	flags   string
}

// TemplateValue is `TemplateElement.value`: `cooked` is null (has_cooked false) in a tagged
// template with an invalid escape.
pub struct TemplateValue {
pub:
	cooked     string
	has_cooked bool
	raw        string
}

// BigIntValue is the value of a BigInt literal (a JavaScript bigint), in decimal digits.
pub struct BigIntValue {
pub:
	digits string
}

// RegExpValue is the value of a regular expression literal that V8 accepts (a RegExp object;
// one it rejects has the value null).
pub struct RegExpValue {}

// prop returns the stored property, if the node has it.
pub fn (t &EsTree) prop(i int, key Key) ?Prop {
	for p in t.nodes[i].props {
		if p.key == key {
			return p
		}
	}
	return none
}

// get returns the value of a property of the node `i`.
pub fn (t &EsTree) get(i int, key Key) Value {
	p := t.prop(i, key) or { return Undefined{} }
	return t.value_of(p)
}

// value_of converts a stored property to a Value.
pub fn (t &EsTree) value_of(p Prop) Value {
	return match p.kind {
		.null { Null{} }
		.bool { p.b }
		.number { p.num }
		.string { p.str }
		.node { NodeRef{p.idx} }
		.list { NodeList{t.lists[p.idx]} }
		.regex { RegexInfo{p.str, p.str2} }
		.template { TemplateValue{p.str, !p.b, p.str2} }
		.bigint { BigIntValue{p.str} }
		.regexp { RegExpValue{} }
	}
}

// node returns the node a property refers to, or none (absent, null or not a node).
pub fn (t &EsTree) node(i int, key Key) ?int {
	p := t.prop(i, key)?
	if p.kind == .node {
		return p.idx
	}
	return none
}

// list returns the list a property holds, or none.
pub fn (t &EsTree) list(i int, key Key) ?[]int {
	p := t.prop(i, key)?
	if p.kind == .list {
		return t.lists[p.idx]
	}
	return none
}

// string_of returns the string a property holds (`name`, `operator`, `raw`…), or none.
pub fn (t &EsTree) string_of(i int, key Key) ?string {
	p := t.prop(i, key)?
	if p.kind == .string {
		return p.str
	}
	return none
}

// flag returns the boolean a property holds, or none.
pub fn (t &EsTree) flag(i int, key Key) ?bool {
	p := t.prop(i, key)?
	if p.kind == .bool {
		return p.b
	}
	return none
}

// typ is the type of the node `i`.
pub fn (t &EsTree) typ(i int) NodeType {
	return t.nodes[i].typ
}

// ts_node is the tree-sitter node the ESTree node was converted from, if any.
pub fn (t &EsTree) ts_node(i int) ?C.TSNode {
	n := t.nodes[i]
	if n.has_ts {
		return n.ts
	}
	return none
}

const keys_by_name = build_keys_by_name()

fn build_keys_by_name() map[string]Key {
	mut m := map[string]Key{}
	for k, name in key_names {
		m[name] = unsafe { Key(k) }
	}
	return m
}

// key_from_name is the Key of an ESTree property name.
pub fn key_from_name(name string) ?Key {
	return keys_by_name[name] or { return none }
}
