module svelte

// The AST the Svelte 5.56.0 compiler's parser builds (`parse(code, {modern: true})`), as far as
// svelte-eslint-parser 1.10.1 reads it, in an arena: CAst.nodes are the template nodes,
// attributes and directives, CAst.exprs the JavaScript expressions and patterns (only their
// extent, kind and comments: svelte-eslint-parser re-parses their text with the script
// parser). Offsets are bytes of the template code (the file with the contents of <script> and
// <style> blanked), which are the file's.

pub enum CType as u8 {
	root
	text
	comment
	expression_tag
	html_tag
	debug_tag
	const_tag
	declaration_tag
	render_tag
	if_block
	each_block
	await_block
	key_block
	snippet_block
	regular_element
	component
	slot_element
	title_element
	svelte_head
	svelte_options
	svelte_window
	svelte_document
	svelte_body
	svelte_element
	svelte_component
	svelte_self
	svelte_fragment
	svelte_boundary
	attribute
	spread_attribute
	attach_tag
	bind_directive
	on_directive
	class_directive
	style_directive
	transition_directive
	animate_directive
	use_directive
	let_directive
	script
	style_sheet
}

const ctype_names = ['Root', 'Text', 'Comment', 'ExpressionTag', 'HtmlTag', 'DebugTag', 'ConstTag',
	'DeclarationTag', 'RenderTag', 'IfBlock', 'EachBlock', 'AwaitBlock', 'KeyBlock', 'SnippetBlock',
	'RegularElement', 'Component', 'SlotElement', 'TitleElement', 'SvelteHead', 'SvelteOptions',
	'SvelteWindow', 'SvelteDocument', 'SvelteBody', 'SvelteElement', 'SvelteComponent', 'SvelteSelf',
	'SvelteFragment', 'SvelteBoundary', 'Attribute', 'SpreadAttribute', 'AttachTag', 'BindDirective',
	'OnDirective', 'ClassDirective', 'StyleDirective', 'TransitionDirective', 'AnimateDirective',
	'UseDirective', 'LetDirective', 'Script', 'StyleSheet']

pub fn (t CType) name() string {
	return ctype_names[int(t)]
}

// is_element tells the element-like types (RegularElement…SvelteBoundary).
pub fn (t CType) is_element() bool {
	return int(t) >= int(CType.regular_element) && int(t) <= int(CType.svelte_boundary)
}

// is_directive tells the directive types.
pub fn (t CType) is_directive() bool {
	return int(t) >= int(CType.bind_directive) && int(t) <= int(CType.let_directive)
}

// AttrValue is the kind of an attribute's value: `true`, one ExpressionTag node, or an array of
// Text and ExpressionTag nodes.
pub enum AttrValue as u8 {
	none // absent (a directive without value)
	true_
	node
	array
}

// CNode is a template node of the compiler AST. Which fields it uses depends on its type.
pub struct CNode {
pub mut:
	typ   CType
	start int
	end   int
	// Elements, attributes, directives: `name`.
	name string
	// Text: `data` (decoded) and `raw`; Comment: `data`.
	data string
	raw  string
	// Elements: `attributes` and `fragment` (an index in CAst.fragments).
	attributes []int
	fragment   int = -1
	// Attributes: the value (`value` holds the node(s)); directives: `expression` (a CExpr) and
	// `modifiers`; TransitionDirective: intro/outro.
	value_kind AttrValue
	value      []int
	modifiers  []string
	intro      bool
	outro      bool
	// Tags and blocks: `expression` (ExpressionTag, HtmlTag, RenderTag, AttachTag,
	// SpreadAttribute, EachBlock, AwaitBlock, KeyBlock, SnippetBlock's name; IfBlock's test;
	// SvelteComponent's expression; SvelteElement's tag).
	expression int = -1
	// IfBlock: elseif, consequent, alternate (fragments).
	elseif     bool
	consequent int = -1
	alternate  int = -1
	// EachBlock: body, fallback, context (a CExpr), index (a string) and key (a CExpr).
	body      int = -1
	fallback  int = -1
	context   int = -1
	index     string
	has_index bool
	key       int = -1
	// AwaitBlock: value and error (CExprs), pending, then and catch (fragments).
	await_value int = -1
	await_error int = -1
	pending     int = -1
	then        int = -1
	catch_      int = -1
	// SnippetBlock: typeParams and parameters (CExprs).
	type_params     string
	has_type_params bool
	parameters      []int
	// DebugTag: identifiers (CExprs).
	identifiers []int
	// ConstTag: the declarator's id and init (CExprs) and the declaration's range.
	decl_id    int = -1
	decl_init  int = -1
	decl_start int
	decl_end   int
	// DeclarationTag: the declaration (`kind` and its range).
	decl_kind string
	// Script: `context` ('default' or 'module'), the content range.
	script_module bool
	content_start int
	content_end   int
	// SvelteOptions: runes when given (`runes` attribute).
	runes     bool
	has_runes bool
}

// ExprKind is what svelte-eslint-parser needs to know of an expression's type.
pub enum ExprKind as u8 {
	other
	identifier
	sequence
	call       // a CallExpression
	chain_call // a ChainExpression whose expression is a CallExpression
	literal    // a string Literal made by the compiler for `this="…"`
	member
	assignment
	object_pattern // a `{…}` pattern
	array_pattern  // a `[…]` pattern
	ts_as
	arrow
}

// CExpr is an expression or a pattern of the compiler AST: its extent (after the compiler's
// remove_parens, so wrapping parentheses are outside), its kind, the comments the compiler
// attached to it (indexes in CAst.comments; svelte-eslint-parser widens its re-parsed range
// over them) and, for a pattern with a TypeScript annotation, the annotation's range.
pub struct CExpr {
pub mut:
	kind      ExprKind
	start     int
	end       int
	name      string // Identifier: name
	leading   []int
	trailing  []int
	elems     []int // SequenceExpression: expressions (CExprs)
	ann_start int = -1 // typeAnnotation (TSTypeAnnotation) range, from the `:`
	ann_end   int = -1
	// synthetic: made by the compiler, not read by acorn (bind:x / class:x without value).
	synthetic bool
	// raw of a compiler Literal (`'…'`).
	raw string
}

// CComment is a JavaScript comment the compiler collected (root.comments).
pub struct CComment {
pub:
	block bool
	start int
	end   int
	value string
}

// CAst is the compiler's Root.
pub struct CAst {
pub mut:
	nodes     []CNode
	fragments [][]int
	exprs     []CExpr
	comments  []CComment
	// root: fragment, options (a SvelteOptions node or -1), instance, module, css.
	fragment int
	options  int = -1
	instance int = -1
	module   int = -1
	css      int = -1
	ts       bool
	// warnings: the warnings of the parse phase (element_implicitly_closed,
	// svelte_element_invalid_this, script_unknown_attribute), in the order they are emitted.
	warnings []CWarning
}

// CWarning is a warning of the compiler's parser: its code, range and message arguments.
pub struct CWarning {
pub:
	code  string
	start int
	end   int
	args  []string
}

fn (mut a CAst) add(n CNode) int {
	a.nodes << n
	return a.nodes.len - 1
}

fn (mut a CAst) new_fragment() int {
	a.fragments << []int{}
	return a.fragments.len - 1
}

fn (mut a CAst) add_expr(e CExpr) int {
	a.exprs << e
	return a.exprs.len - 1
}

// CompileError is a parse error of the compiler: `code`, `message` (ending with
// `\nhttps://svelte.dev/e/<code>`) and the start of its position (a byte offset).
pub struct CompileError {
	Error
pub:
	code    string
	message string
	pos     int
}

pub fn (e CompileError) msg() string {
	return e.message
}

fn compile_error(code string, message string, pos int) IError {
	return CompileError{
		code:    code
		message: '${message}\nhttps://svelte.dev/e/${code}'
		pos:     pos
	}
}
