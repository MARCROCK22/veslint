module svelte

// The AST svelte-eslint-parser 1.10.1 builds for a .svelte file (its SvelteProgram and Svelte*
// nodes, src/ast/html.ts), in an arena: Document.nodes, nodes[0] being the Program. Svelte nodes
// refer to each other by index (-1: none); the ESTree nodes of the scripts and of the template
// expressions are nodes of Document.es (one tree for the whole file, see script_let.v), referred
// to with Ref. Every position is a byte offset of the file (Document.loc / utf16 give what
// svelte-eslint-parser reports).

pub enum SType as u8 {
	program
	script_element
	style_element
	element
	start_tag
	end_tag
	name
	member_expression_name
	text
	literal
	mustache_tag
	debug_tag
	const_tag
	declaration_tag
	render_tag
	if_block
	else_block
	each_block
	await_block
	await_pending_block
	await_then_block
	await_catch_block
	key_block
	snippet_block
	attribute
	shorthand_attribute
	spread_attribute
	attach_tag
	directive
	style_directive
	special_directive
	generics_directive
	directive_key
	special_directive_key
	html_comment
}

const stype_names = ['Program', 'SvelteScriptElement', 'SvelteStyleElement', 'SvelteElement',
	'SvelteStartTag', 'SvelteEndTag', 'SvelteName', 'SvelteMemberExpressionName', 'SvelteText',
	'SvelteLiteral', 'SvelteMustacheTag', 'SvelteDebugTag', 'SvelteConstTag', 'SvelteDeclarationTag',
	'SvelteRenderTag', 'SvelteIfBlock', 'SvelteElseBlock', 'SvelteEachBlock', 'SvelteAwaitBlock',
	'SvelteAwaitPendingBlock', 'SvelteAwaitThenBlock', 'SvelteAwaitCatchBlock', 'SvelteKeyBlock',
	'SvelteSnippetBlock', 'SvelteAttribute', 'SvelteShorthandAttribute', 'SvelteSpreadAttribute',
	'SvelteAttachTag', 'SvelteDirective', 'SvelteStyleDirective', 'SvelteSpecialDirective',
	'SvelteGenericsDirective', 'SvelteDirectiveKey', 'SvelteSpecialDirectiveKey', 'SvelteHTMLComment']

pub fn (t SType) type_name() string {
	return stype_names[int(t)]
}

// Ref is a property holding a node that may be a Svelte node or an ESTree node.
pub struct Ref {
pub:
	es  bool
	idx int = -1
}

pub const no_ref = Ref{}

pub fn (r Ref) is_null() bool {
	return r.idx < 0
}

fn sref(i int) Ref {
	return Ref{
		es:  false
		idx: i
	}
}

fn eref(i int) Ref {
	return Ref{
		es:  true
		idx: i
	}
}

// SNode is a Svelte node. Which fields a node uses depends on its type (see json.v for the
// properties of each type, in svelte-eslint-parser's order).
pub struct SNode {
pub mut:
	typ    SType
	start  int
	end    int
	parent int = -1
	// kind: SvelteElement ('html', 'component', 'special'), SvelteMustacheTag ('text', 'raw'),
	// SvelteDirective ('Binding', 'EventHandler', 'Class', 'Transition', 'Animation', 'Action',
	// 'Let'), SvelteSpecialDirective ('this'), SvelteAwaitBlock ('await', 'await-then',
	// 'await-catch').
	kind string
	// SvelteName: name; SvelteText, SvelteLiteral, SvelteHTMLComment: value.
	name  string
	value string
	// Elements: name (a SvelteName, an ESTree Identifier or a SvelteMemberExpressionName),
	// startTag, children, endTag. SvelteScriptElement: body (ESTree statements).
	name_ref  Ref
	start_tag int = -1
	end_tag   int = -1
	children  []int
	body      []int // ESTree statements
	// SvelteStartTag: attributes, selfClosing.
	attributes   []int
	self_closing bool
	// Attributes and directives: key (SvelteName, ESTree Identifier, SvelteDirectiveKey,
	// SvelteSpecialDirectiveKey), boolean, value (Svelte nodes), shorthand; expression (ESTree,
	// or null). SvelteShorthandAttribute: key and value are ESTree Identifiers. SvelteDirective
	// Transition: intro, outro. SvelteDirectiveKey: name (Ref), modifiers.
	key        Ref
	boolean    bool
	values     []int
	value_ref  Ref
	shorthand  bool
	expression Ref
	intro      bool
	outro      bool
	modifiers  []string
	// SvelteFunctionBindingsExpression: the directive's expression had its type renamed.
	function_bindings bool
	// SvelteMemberExpressionName: object (Ref) and property (a SvelteName).
	object   Ref
	property int = -1
	// Blocks: elseif, else (a SvelteElseBlock), context, index, key_expr (ESTree), pending,
	// then, catch (Svelte nodes), awaitThen/awaitCatch, value/error (ESTree), id and params
	// (ESTree, snippets).
	elseif      bool
	else_       int = -1
	context     Ref
	index_ref   Ref
	key_expr    Ref
	pending     int = -1
	then        int = -1
	catch_      int = -1
	await_then  bool
	await_catch bool
	value_es    Ref
	error_es    Ref
	id          Ref
	params      []int // ESTree
	// SvelteDebugTag: identifiers; SvelteConstTag: declarations (ESTree);
	// SvelteDeclarationTag: declaration (ESTree).
	identifiers  []int
	declarations []int
	declaration  Ref
	// SvelteGenericsDirective: params (ESTree TSTypeParameters).
	generic_params []int
	// loc overrides: where `loc` differs from the range (-1: none). Byte offsets.
	loc_end int = -1
}

// Token is a token or a comment of the document. Comments have type `Line` or `Block` and
// value without the delimiters. loc_start/loc_end, when not -1, are byte offsets `loc` is
// computed from instead of the range (the `extends` token of generics keeps a stale loc).
pub struct Token {
pub mut:
	typ       string
	start     int
	end       int
	value     string
	loc_start int = -1
	loc_end   int = -1
}

// ParseError is the error svelte-eslint-parser throws (one per file). `ts_message`: the error
// comes from typescript-eslint's parser (a syntax error of the code it is handed, see
// Document.script_code): `message` is then a guess and the real one is TypeScript's first
// syntactic diagnostic of that code (map its position with Document.virtual_to_file). `index`
// is a byte offset of the file, or, past its end, of the code handed to the script parser
// beyond it (svelte-eslint-parser reports those positions as they are).
pub struct ParseError {
pub mut:
	message    string
	index      int
	ts_message bool
	// pre_index: for a ts_message error, the byte offset in the pre-virtual code.
	pre_index int = -1
	// compiler: a Svelte compiler error (its code).
	code string
}
