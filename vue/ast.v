module vue

import estree

// The document of a .vue file as vue-eslint-parser 10.4.2 builds it (its VDocumentFragment, see
// .claude/vue-parser-spec.md), in an arena: the V* nodes are Document.nodes and refer to each other
// by index (-1 is no node); the ESTree of each template expression lives in the EsTree of the
// snippet it was parsed from (Document.snippets). Every position is a byte offset of the file;
// Document.loc gives vue-eslint-parser's `loc` of one (lines broken by LF only, UTF-16 columns).

// NodeType is the `type` of a V* node.
pub enum NodeType as u8 {
	v_document_fragment
	v_element
	v_start_tag
	v_end_tag
	v_attribute
	v_identifier
	v_directive_key
	v_literal
	v_text
	v_expression_container
	v_for_expression
	v_on_expression
	v_slot_scope_expression
	v_generic_expression
	v_filter_sequence_expression
	v_filter
}

const node_type_names = ['VDocumentFragment', 'VElement', 'VStartTag', 'VEndTag', 'VAttribute',
	'VIdentifier', 'VDirectiveKey', 'VLiteral', 'VText', 'VExpressionContainer', 'VForExpression',
	'VOnExpression', 'VSlotScopeExpression', 'VGenericExpression', 'VFilterSequenceExpression',
	'VFilter']

// type_name is the ESTree-style name of the type (`VElement`…).
pub fn (t NodeType) type_name() string {
	return node_type_names[int(t)]
}

// Namespace is the namespace of an element.
pub enum Namespace as u8 {
	html
	svg
	mathml
}

pub const ns_html = 'http://www.w3.org/1999/xhtml'
pub const ns_svg = 'http://www.w3.org/2000/svg'
pub const ns_mathml = 'http://www.w3.org/1998/Math/MathML'
pub const ns_xlink = 'http://www.w3.org/1999/xlink'

// uri is the namespace as vue-eslint-parser writes it.
pub fn (n Namespace) uri() string {
	return match n {
		.html { ns_html }
		.svg { ns_svg }
		.mathml { ns_mathml }
	}
}

// ExprKind tells what an Expr refers to.
pub enum ExprKind as u8 {
	null
	estree // a node of the ESTree of a snippet
	vnode  // a V* node (VForExpression, VOnExpression, VFilterSequenceExpression…)
}

// Expr is the value of a property that holds a script node (an expression, a pattern, a statement)
// or one of the V* nodes that wrap them.
pub struct Expr {
pub:
	kind    ExprKind
	snippet int = -1 // with .estree: the index in Document.snippets
	node    int = -1 // the index in that snippet's EsTree, or in Document.nodes
}

pub const no_expr = Expr{}

pub fn (e Expr) is_null() bool {
	return e.kind == .null
}

// VNode is a V* node. Which fields a node uses depends on its type; the others stay empty.
pub struct VNode {
pub mut:
	typ    NodeType
	start  int
	end    int
	parent int = -1
	// loc_start and loc_end, when not -1, are where `loc` starts and ends instead (a
	// VOnExpression without statements takes them from other places than its range).
	loc_start int = -1
	loc_end   int = -1
	// VElement and VIdentifier: `name` and `rawName`.
	name     string
	raw_name string
	// VElement.
	namespace Namespace
	start_tag int = -1
	end_tag   int = -1
	children  []int // also of a VDocumentFragment
	variables []int // indexes in Document.variables
	style     bool  // a top-level <style> (VStyleElement)
	// VStartTag.
	self_closing bool
	attributes   []int
	// VAttribute: `key` is a VIdentifier, or a VDirectiveKey when `directive`; `value` a VLiteral,
	// or a VExpressionContainer when `directive`.
	directive bool
	key       int = -1
	value     int = -1
	// VDirectiveKey: `name` (dir_name) and `argument` (a VIdentifier or a VExpressionContainer).
	dir_name  int = -1
	argument  int = -1
	modifiers []int
	// VLiteral and VText: `value`.
	text string
	// VExpressionContainer: `expression` (null, an ESTree expression or a V* expression) and
	// `references` (indexes in Document.references). VFilterSequenceExpression: `expression` and
	// `filters`. VForExpression: `left` (exprs) and `right`. VOnExpression: `body` (exprs).
	// VSlotScopeExpression and VGenericExpression: `params` (exprs), and `rawParams`.
	// VFilter: `callee` (an Identifier made by vue-eslint-parser: callee_name at
	// [callee_start, callee_end)) and `arguments` (exprs).
	expression   Expr
	references   []int
	exprs        []Expr
	right        Expr
	raw_params   []string
	filters      []int
	callee_name  string
	callee_start int
	callee_end   int
}

// Token is a token or a comment of the document: an HTML token (`HTMLTagOpen`…), a token of a
// directive key or of a template expression (`Punctuator`, `Identifier`, `Keyword`…), or a
// comment (`HTMLComment`, `HTMLBogusComment`, `Line`, `Block`).
pub struct Token {
pub mut:
	typ   string
	start int
	end   int
	value string
}

// ParseError is an error of the document: an HTML parse error (`code` is its code, which is also
// the message) or an error of a template expression (no code). `ts_message`: vue-eslint-parser
// reports there the first syntactic diagnostic TypeScript gives for the code of the snippet
// `snippet`, which tree-sitter cannot give: `message` is a guess and `index` where tree-sitter
// found the error. To have the real one, parse Snippet.code with TypeScript (tsgo), map the
// diagnostic's start with Snippet.utf16_to_file, and when `adjust_end` is not -1 and the mapped
// offset is at or past it, the message is "Unexpected end of expression.".
pub struct ParseError {
pub mut:
	message    string
	code       string
	index      int
	ts_message bool
	snippet    int = -1
	adjust_end int = -1
	// line and column, when line is not 0, are the error's lineNumber and column instead of the
	// location of `index`: the tokenizer reports the errors of the input stream with the location
	// of the previous code point.
	line   int
	column int
}

// Reference is a reference of a template expression to something outside it (vue-eslint-parser's
// Reference): `id` is its Identifier, `mode` `r`, `w` or `rw`, `variable` the Variable of an
// enclosing v-for, v-slot or generic it resolves to (-1: none). `has_kind` is false for the
// reference of a same-name shorthand (`:foo`), which has no isValueReference/isTypeReference.
pub struct Reference {
pub mut:
	id                 Expr
	name               string
	mode               string
	variable           int = -1
	is_value_reference bool
	is_type_reference  bool
	has_kind           bool
}

// Variable is a variable a v-for, a slot scope or a generic defines (`kind` `v-for`, `scope`,
// `generic`), with the references that resolve to it.
pub struct Variable {
pub mut:
	id         Expr
	name       string
	kind       string
	references []int
}

// Snippet is a piece of code vue-eslint-parser hands to the script parser for a template
// expression (`0(…)`, `void function($event){…}`, `for(let […] in …);`…), parsed by tree-sitter.
// The nodes of `es` have file offsets (their `ts` nodes keep the snippet's: see file_offset).
pub struct Snippet {
pub:
	code string
	tsx  bool
pub mut:
	tree &C.vt_rows = unsafe { nil }
	es   estree.EsTree
	// to_file maps each byte offset of `code` (and its end) to a byte offset of the file.
	to_file []int
}

// utf16_to_file maps a UTF-16 offset of the snippet's code (a TypeScript position) to a byte
// offset of the file.
pub fn (s &Snippet) utf16_to_file(u int) int {
	return s.file_offset(new_text_index(s.code).to_byte(u))
}

// file_offset maps a byte offset of the snippet's code (a tree-sitter position) to the file.
pub fn (s &Snippet) file_offset(offset int) int {
	if offset < 0 {
		return s.to_file[0]
	}
	if offset >= s.to_file.len {
		return s.to_file[s.to_file.len - 1]
	}
	return s.to_file[offset]
}
