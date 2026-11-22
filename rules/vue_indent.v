module rules

import esquery
import estree
import json2
import math
import time
import treesitter { Ident }
import vue

// Port of eslint-plugin-vue 10.12.1's indentation engine (lib/utils/indent-common.ts,
// indent-ts.ts and indent-utils.ts), shared by `vue/html-indent` (the template of a .vue file,
// through defineTemplateBodyVisitor and the template token store) and `vue/script-indent` (the
// <script> of a .vue file, through ESLint's traversal and sourceCode's token store). Like upstream
// it runs in two passes: while the traversal enters the nodes, each node's listener records the
// offset of some of its tokens from a base token; when the traversal leaves the top-level node
// (the Program, or the template's root element), the lines are validated one by one, the first
// token of each line taking its expected indentation from its base's.
//
// Files: this one (options, token store, offsets, validation, the dispatch of the listeners and
// the two rules), vue_indent_es.v (the ES and Vue listeners of indent-common.ts) and
// vue_indent_ts.v (indent-ts.ts). Every helper has the prefix `vind_`.
//
// Faithfulness notes:
//   - The token store is vue-eslint-parser's copy of ESLint's TokenStore for the template and
//     ESLint's own for the script, on UTF-16 offsets as in JavaScript: both find the tokens of a
//     range through an index map of the token starts and ends, and differ when a range starts
//     where no token starts or ends (VindStore.first_index).
//   - The listeners of one node run in the order ESLint's (and vue-eslint-parser's) event
//     generators call them: by the selector's specificity (attributes, then identifiers; a
//     `:class` counts for neither), then by its text (VindCtx.enter).
//   - An offset is an object that two tokens may share (processSemicolons gives the `;` before a
//     line the object of the line's first token): tokens point to entries of VindCtx.datas.

const vind_unexpected_char = 'Expected {{expected}} character, but found {{actual}} character.'
const vind_unexpected_indentation = 'Expected indentation of {{expectedIndent}} {{unit}}{{expectedIndentPlural}} but found {{actualIndent}} {{unit}}{{actualIndentPlural}}.'

// The node types the listeners name (knownNodes): the tokens of any other node are ignored when
// the traversal leaves it.
const vind_known_types = ['AccessorProperty', 'ArrayExpression', 'ArrayPattern',
	'ArrowFunctionExpression', 'AssignmentExpression', 'AssignmentPattern', 'AwaitExpression',
	'BinaryExpression', 'BlockStatement', 'BreakStatement', 'CallExpression', 'CatchClause',
	'ChainExpression', 'ClassBody', 'ClassDeclaration', 'ClassExpression', 'ClassProperty',
	'ConditionalExpression', 'ContinueStatement', 'DebuggerStatement', 'Decorator', 'DoWhileStatement',
	'EmptyStatement', 'ExportAllDeclaration', 'ExportDefaultDeclaration', 'ExportNamedDeclaration',
	'ExportSpecifier', 'ExpressionStatement', 'ForInStatement', 'ForOfStatement', 'ForStatement',
	'FunctionDeclaration', 'FunctionExpression', 'Identifier', 'IfStatement', 'ImportAttribute',
	'ImportDeclaration', 'ImportDefaultSpecifier', 'ImportExpression', 'ImportNamespaceSpecifier',
	'ImportSpecifier', 'LabeledStatement', 'Literal', 'LogicalExpression', 'MemberExpression',
	'MetaProperty', 'MethodDefinition', 'NewExpression', 'ObjectExpression', 'ObjectPattern',
	'PrivateIdentifier', 'Program', 'Property', 'PropertyDefinition', 'RestElement', 'ReturnStatement',
	'SequenceExpression', 'SpreadElement', 'StaticBlock', 'Super', 'SwitchCase', 'SwitchStatement',
	'TaggedTemplateExpression', 'TemplateElement', 'TemplateLiteral', 'ThisExpression', 'ThrowStatement',
	'TryStatement', 'TSAbstractAccessorProperty', 'TSAbstractClassProperty', 'TSAbstractKeyword',
	'TSAbstractMethodDefinition', 'TSAbstractPropertyDefinition', 'TSAnyKeyword', 'TSArrayType',
	'TSAsExpression', 'TSAsyncKeyword', 'TSBigIntKeyword', 'TSBooleanKeyword',
	'TSCallSignatureDeclaration', 'TSClassImplements', 'TSConditionalType', 'TSConstructorType',
	'TSConstructSignatureDeclaration', 'TSDeclareFunction', 'TSDeclareKeyword',
	'TSEmptyBodyFunctionExpression', 'TSEnumBody', 'TSEnumDeclaration', 'TSEnumMember',
	'TSExportAssignment', 'TSExportKeyword', 'TSExternalModuleReference', 'TSFunctionType',
	'TSImportEqualsDeclaration', 'TSImportType', 'TSIndexedAccessType', 'TSIndexSignature',
	'TSInferType', 'TSInstantiationExpression', 'TSInterfaceBody', 'TSInterfaceDeclaration',
	'TSInterfaceHeritage', 'TSIntersectionType', 'TSIntrinsicKeyword', 'TSJSDocNonNullableType',
	'TSLiteralType', 'TSMappedType', 'TSMethodSignature', 'TSModuleBlock', 'TSModuleDeclaration',
	'TSNamedTupleMember', 'TSNamespaceExportDeclaration', 'TSNeverKeyword', 'TSNonNullExpression',
	'TSNullKeyword', 'TSNumberKeyword', 'TSObjectKeyword', 'TSOptionalType', 'TSParameterProperty',
	'TSParenthesizedType', 'TSPrivateIdentifier', 'TSPrivateKeyword', 'TSPropertySignature',
	'TSProtectedKeyword', 'TSPublicKeyword', 'TSQualifiedName', 'TSReadonlyKeyword', 'TSRestType',
	'TSSatisfiesExpression', 'TSStaticKeyword', 'TSStringKeyword', 'TSSymbolKeyword',
	'TSTemplateLiteralType', 'TSThisType', 'TSTupleType', 'TSTypeAliasDeclaration', 'TSTypeAnnotation',
	'TSTypeAssertion', 'TSTypeLiteral', 'TSTypeOperator', 'TSTypeParameter',
	'TSTypeParameterDeclaration', 'TSTypeParameterInstantiation', 'TSTypePredicate', 'TSTypeQuery',
	'TSTypeReference', 'TSUndefinedKeyword', 'TSUnionType', 'TSUnknownKeyword', 'TSVoidKeyword',
	'UnaryExpression', 'UpdateExpression', 'VariableDeclaration', 'VariableDeclarator', 'VAttribute',
	'VDirectiveKey', 'VElement', 'VEndTag', 'VExpressionContainer', 'VFilter',
	'VFilterSequenceExpression', 'VForExpression', 'VIdentifier', 'VLiteral', 'VOnExpression',
	'VSlotScopeExpression', 'VStartTag', 'VText', 'WhileStatement', 'WithStatement', 'YieldExpression']

const vind_known = build_vind_known()

fn build_vind_known() map[string]bool {
	mut m := map[string]bool{}
	for t in vind_known_types {
		m[t] = true
	}
	return m
}

// ---------------------------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------------------------

struct VindOptions {
mut:
	indent_char u8  = ` `
	indent_size int = 2
	base_indent int
	attribute   int = 1
	close_start int
	close_end   int
	close_self  int
	switch_case int
	align       bool = true
	ignores     []string
}

// vind_safe_int is the value when Number.isSafeInteger holds for it.
fn vind_safe_int(v json2.Any) ?int {
	if v is string || v is bool || v is json2.Null || v is map[string]json2.Any || v is []json2.Any {
		return none
	}
	n := json_number(v)
	if n != math.floor(n) || math.abs(n) > 9007199254740991.0 {
		return none
	}
	return int(n)
}

// vind_options is parseOptions (the schema has been checked): `base_indent` is the rule's default
// baseIndent (1 for html-indent, 0 for script-indent).
fn vind_options(options []json2.Any, base_indent int) VindOptions {
	mut o := VindOptions{
		base_indent: base_indent
	}
	if options.len > 0 {
		if n := vind_safe_int(options[0]) {
			o.indent_size = n
		} else if options[0] is string && options[0] as string == 'tab' {
			o.indent_char = `\t`
			o.indent_size = 1
		}
	}
	if options.len < 2 || options[1] !is map[string]json2.Any {
		return o
	}
	m := options[1] as map[string]json2.Any
	if v := m['baseIndent'] {
		if n := vind_safe_int(v) {
			o.base_indent = n
		}
	}
	if v := m['attribute'] {
		if n := vind_safe_int(v) {
			o.attribute = n
		}
	}
	if v := m['closeBracket'] {
		if n := vind_safe_int(v) {
			o.close_start = n
			o.close_end = n
			o.close_self = n
		} else if v is map[string]json2.Any {
			if n := vind_safe_int(v['startTag'] or { json2.Any(json2.null) }) {
				o.close_start = n
			}
			if n := vind_safe_int(v['endTag'] or { json2.Any(json2.null) }) {
				o.close_end = n
			}
			if n := vind_safe_int(v['selfClosingTag'] or { json2.Any(json2.null) }) {
				o.close_self = n
			}
		}
	}
	if v := m['switchCase'] {
		if n := vind_safe_int(v) {
			o.switch_case = n
		}
	}
	if v := m['alignAttributesVertically'] {
		if v is bool {
			o.align = v
		}
	}
	if v := m['ignores'] {
		if v is []json2.Any {
			o.ignores = v.filter(it is string).map(it as string)
		}
	}
	return o
}

// ---------------------------------------------------------------------------------------------
// Tokens and the token store
// ---------------------------------------------------------------------------------------------

// VindTok is a token or a comment: its range in bytes of the file (start, end) and in UTF-16
// units (us, ue), and its location as vue-eslint-parser gives it (lines end at LF only).
struct VindTok {
	typ      string
	value    string
	start    int
	end      int
	us       int
	ue       int
	comment  bool
	line     int
	end_line int
	column   int
}

// VindStore is a TokenStore: `all` are the tokens and the comments by start, `code` and `cmts`
// the indexes in `all` of the tokens and of the comments (the arrays the original has), `imap` its
// index map (UTF-16 offset -> index in `code`). `eslint`: ESLint's store (sourceCode), else
// vue-eslint-parser's copy (the template's).
struct VindStore {
mut:
	all    []VindTok
	code   []int
	cmts   []int
	imap   map[int]int
	eslint bool
}

// VindFilter is the `filter` of a token query.
enum VindFilter {
	none_
	not_ws       // isNotWhitespace
	html_content // HTML_CONTENT_TOKEN_TYPES
	open_paren   // isOpeningParenToken
	close_paren  // isClosingParenToken
	not_close_paren
	not_open_paren
	open_brace
	close_brace
	open_bracket
	close_bracket
	arrow
	not_semicolon
	pipe       // isPipeOperator
	extends_kw // isExtendsKeyword
	optional   // isOptionalToken
}

fn vind_punct(t &VindTok, v string) bool {
	return t.typ == 'Punctuator' && t.value == v
}

fn vind_pass(t &VindTok, f VindFilter) bool {
	return match f {
		.none_ { true }
		.not_ws { t.typ != 'HTMLWhitespace' && (t.typ != 'JSXText' || !vind_blank(t.value)) }
		.html_content {
			t.typ in ['HTMLText', 'HTMLRCDataText', 'HTMLTagOpen', 'HTMLEndTagOpen', 'HTMLComment']
		}
		.open_paren { vind_punct(t, '(') }
		.close_paren { vind_punct(t, ')') }
		.not_close_paren { !vind_punct(t, ')') }
		.not_open_paren { !vind_punct(t, '(') }
		.open_brace { vind_punct(t, '{') }
		.close_brace { vind_punct(t, '}') }
		.open_bracket { vind_punct(t, '[') }
		.close_bracket { vind_punct(t, ']') }
		.arrow { vind_punct(t, '=>') }
		.not_semicolon { !vind_punct(t, ';') }
		.pipe { vind_punct(t, '|') }
		.extends_kw { t.typ == 'Keyword' && t.value == 'extends' }
		.optional { vind_punct(t, '?.') }
	}
}

// vind_blank: `!value.trim()`.
fn vind_blank(s string) bool {
	for r in s.runes() {
		if !is_js_space(r) {
			return false
		}
	}
	return true
}

// vind_is_comment is isComment of indent-utils.ts.
fn vind_is_comment(t &VindTok) bool {
	return t.typ in ['Block', 'Line', 'Shebang'] || t.typ.ends_with('Comment')
}

// new_vind_store builds the store of the tokens and comments (each sorted by start).
fn new_vind_store(doc &vue.Document, tokens []vue.Token, comments []vue.Token, eslint bool) VindStore {
	mut s := VindStore{
		eslint: eslint
	}
	mut i := 0
	mut j := 0
	for i < tokens.len || j < comments.len {
		take_token := j >= comments.len || (i < tokens.len && tokens[i].start < comments[j].start)
		t := if take_token { tokens[i] } else { comments[j] }
		start_loc := doc.loc(t.start)
		end_loc := doc.loc(t.end)
		if take_token {
			s.code << s.all.len
			i++
		} else {
			s.cmts << s.all.len
			j++
		}
		s.all << VindTok{
			typ:      t.typ
			value:    t.value
			start:    t.start
			end:      t.end
			us:       doc.utf16(t.start)
			ue:       doc.utf16(t.end)
			comment:  !take_token
			line:     start_loc.line
			end_line: end_loc.line
			column:   start_loc.column
		}
	}
	// createIndexMap.
	mut ti := 0
	mut ci := 0
	for ti < s.code.len || ci < s.cmts.len {
		mut next_start := if ci < s.cmts.len { s.all[s.cmts[ci]].us } else { max_int }
		for ti < s.code.len && s.all[s.code[ti]].us < next_start {
			t := s.all[s.code[ti]]
			s.imap[t.us] = ti
			s.imap[t.ue - 1] = ti
			ti++
		}
		next_start = if ti < s.code.len { s.all[s.code[ti]].us } else { max_int }
		for ci < s.cmts.len && s.all[s.cmts[ci]].us < next_start {
			t := s.all[s.cmts[ci]]
			s.imap[t.us] = ti
			s.imap[t.ue - 1] = ti
			ci++
		}
	}
	return s
}

// first_index is getFirstIndex (ESLint's, or vue-eslint-parser's when not `eslint`).
fn (s &VindStore) first_index(start int) int {
	if s.eslint && start == -1 {
		return 0
	}
	if k := s.imap[start] {
		return k
	}
	if k := s.imap[start - 1] {
		if k < 0 || k >= s.code.len {
			return if s.eslint { s.code.len } else { k + 1 }
		}
		if s.all[s.code[k]].us >= start {
			return k
		}
		return k + 1
	}
	if s.eslint {
		return if start == 0 { 0 } else { s.code.len }
	}
	return 0
}

// last_index is getLastIndex.
fn (s &VindStore) last_index(end int) int {
	if s.eslint && end == -1 {
		return s.code.len - 1
	}
	if k := s.imap[end] {
		return k - 1
	}
	if k := s.imap[end - 1] {
		if k < 0 || k >= s.code.len {
			return if s.eslint { s.code.len - 1 } else { k }
		}
		if s.all[s.code[k]].ue > end {
			return k - 1
		}
		return k
	}
	if s.eslint {
		return if end == 0 { -1 } else { s.code.len - 1 }
	}
	return s.code.len - 1
}

// search_comments is utils.search on the comments: the first one that starts at or after `loc`.
fn (s &VindStore) search_comments(loc int) int {
	mut lo := 0
	mut hi := s.cmts.len
	for lo < hi {
		mid := (lo + hi) / 2
		if s.all[s.cmts[mid]].us < loc {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// cursor runs a cursor of the store from `start` to `end` (UTF-16 offsets, -1 for none) with
// the decorations of createCursor (filter, then skip, then count; count -1: all): the indexes in
// `all` of what it gives.
fn (s &VindStore) cursor(forward bool, start int, end int, comments bool, f VindFilter, skip int, count int) []int {
	mut out := []int{}
	if count == 0 {
		return out
	}
	mut skipped := 0
	mut k := if forward { s.first_index(start) } else { s.last_index(end) }
	k_end := if forward { s.last_index(end) } else { s.first_index(start) }
	mut j := if forward { s.search_comments(start) } else { s.search_comments(end) - 1 }
	for {
		mut idx := -1
		if !comments {
			if (forward && k > k_end) || (!forward && k < k_end) || k < 0 || k >= s.code.len {
				break
			}
			idx = s.code[k]
			k += if forward { 1 } else { -1 }
		} else {
			has_token := k >= 0 && k < s.code.len
			has_comment := j >= 0 && j < s.cmts.len
			take_token := has_token && (!has_comment || if forward {
				s.all[s.code[k]].us < s.all[s.cmts[j]].us
			} else {
				s.all[s.code[k]].ue > s.all[s.cmts[j]].ue
			})
			if take_token {
				idx = s.code[k]
				k += if forward { 1 } else { -1 }
			} else if has_comment {
				idx = s.cmts[j]
				j += if forward { 1 } else { -1 }
			} else {
				break
			}
			if forward && end != -1 && s.all[idx].ue > end {
				break
			}
			if !forward && start != -1 && s.all[idx].us < start {
				break
			}
		}
		if !vind_pass(&s.all[idx], f) {
			continue
		}
		if skipped < skip {
			skipped++
			continue
		}
		out << idx
		if count > 0 && out.len >= count {
			break
		}
	}
	return out
}

fn vind_one(list []int) int {
	return if list.len > 0 { list[0] } else { -1 }
}

// ---------------------------------------------------------------------------------------------
// Nodes
// ---------------------------------------------------------------------------------------------

// VindNode is a node of the traversal: a V* node (`v`), the Identifier vue-eslint-parser makes
// for the callee of the VFilter `v` (`callee`), or an ESTree node `es` of the snippet `sn` of the
// template or (sn -1) of the script.
struct VindNode {
	v      int = -1
	sn     int = -1
	es     int = -1
	callee bool
}

fn (n VindNode) ok() bool {
	return n.v >= 0 || n.es >= 0
}

fn (n VindNode) key() u64 {
	return (u64(u32(n.sn + 1)) << 32) | u64(u32(n.es))
}

// VindItem is a node, a token or null as the helpers take them (range in UTF-16 units, lines of
// its `loc`).
struct VindItem {
	s     int
	e     int
	sline int
	eline int
	ok    bool
}

struct VindOff {
mut:
	base         int = -1
	offset       int
	baseline     bool
	expected     int
	has_expected bool
}

@[heap]
struct VindCtx {
mut:
	doc     &vue.Document  = unsafe { nil }
	script  &estree.EsTree = unsafe { nil }
	opts    VindOptions
	st      VindStore
	offs    []int // per token of st.all: index in datas, or -1
	datas   []VindOff
	ignored []bool
	// parents are the parents of the ESTree nodes of the template the traversal visits.
	parents  map[u64]VindNode
	findings []Finding
}

fn (x &VindCtx) tree(sn int) &estree.EsTree {
	return if sn < 0 { x.script } else { &x.doc.snippets[sn].es }
}

fn (x &VindCtx) typ(n VindNode) string {
	if n.callee {
		return 'Identifier'
	}
	if n.v >= 0 {
		return x.doc.nodes[n.v].typ.type_name()
	}
	if n.es >= 0 {
		return x.tree(n.sn).nodes[n.es].typ.type_name()
	}
	return ''
}

// range is the node's range in bytes.
fn (x &VindCtx) range(n VindNode) (int, int) {
	if n.callee {
		node := &x.doc.nodes[n.v]
		return node.callee_start, node.callee_end
	}
	if n.v >= 0 {
		node := &x.doc.nodes[n.v]
		return node.start, node.end
	}
	node := &x.tree(n.sn).nodes[n.es]
	return node.start, node.end
}

// item is the node as a VindItem (null for a null node).
fn (x &VindCtx) item(n VindNode) VindItem {
	if !n.ok() {
		return VindItem{}
	}
	start, end := x.range(n)
	mut ls, mut le := start, end
	if n.v >= 0 && !n.callee {
		node := &x.doc.nodes[n.v]
		if node.loc_start >= 0 {
			ls = node.loc_start
		}
		if node.loc_end >= 0 {
			le = node.loc_end
		}
	}
	return VindItem{
		s:     x.doc.utf16(start)
		e:     x.doc.utf16(end)
		sline: x.doc.loc(ls).line
		eline: x.doc.loc(le).line
		ok:    true
	}
}

fn (x &VindCtx) titem(t int) VindItem {
	if t < 0 {
		return VindItem{}
	}
	tok := &x.st.all[t]
	return VindItem{
		s:     tok.us
		e:     tok.ue
		sline: tok.line
		eline: tok.end_line
		ok:    true
	}
}

fn (x &VindCtx) parent(n VindNode) VindNode {
	if n.callee {
		return VindNode{
			v: n.v
		}
	}
	if n.v >= 0 {
		p := x.doc.nodes[n.v].parent
		if p < 0 {
			return VindNode{}
		}
		return VindNode{
			v: p
		}
	}
	if n.es < 0 {
		return VindNode{}
	}
	if n.sn < 0 {
		p := x.script.nodes[n.es].parent
		if p < 0 {
			return VindNode{}
		}
		return VindNode{
			es: p
		}
	}
	return x.parents[n.key()] or { VindNode{} }
}

// child is the node of the property `key` of an ESTree node (null when it has none).
fn (x &VindCtx) child(n VindNode, key estree.Key) VindNode {
	if n.es < 0 {
		return VindNode{}
	}
	i := x.tree(n.sn).node(n.es, key) or { return VindNode{} }
	return VindNode{
		sn: n.sn
		es: i
	}
}

// list are the nodes of the array property `key` (null nodes for the holes).
fn (x &VindCtx) list(n VindNode, key estree.Key) []VindNode {
	if n.es < 0 {
		return []
	}
	items := x.tree(n.sn).list(n.es, key) or { return [] }
	return items.map(VindNode{
		sn: n.sn
		es: it
	})
}

fn (x &VindCtx) flag(n VindNode, key estree.Key) bool {
	if n.es < 0 {
		return false
	}
	return x.tree(n.sn).flag(n.es, key) or { false }
}

fn vind_expr(e vue.Expr) VindNode {
	return match e.kind {
		.null {
			VindNode{}
		}
		.vnode {
			VindNode{
				v: e.node
			}
		}
		.estree {
			VindNode{
				sn: e.snippet
				es: e.node
			}
		}
	}
}

fn (x &VindCtx) items(list []VindNode) []VindItem {
	return list.map(x.item(it))
}

// ---------------------------------------------------------------------------------------------
// Token queries on items
// ---------------------------------------------------------------------------------------------

// ft is getFirstToken(item) (-1: null); ftf with a filter, fts with a skip.
fn (x &VindCtx) ft(it VindItem) int {
	return x.fts(it, 0)
}

fn (x &VindCtx) ftf(it VindItem, f VindFilter) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(true, it.s, it.e, false, f, 0, 1))
}

fn (x &VindCtx) fts(it VindItem, skip int) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(true, it.s, it.e, false, .none_, skip, 1))
}

// lt is getLastToken(item); ltf with a filter.
fn (x &VindCtx) lt(it VindItem) int {
	return x.ltf(it, .none_)
}

fn (x &VindCtx) ltf(it VindItem, f VindFilter) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(false, it.s, it.e, false, f, 0, 1))
}

// tb is getTokenBefore(item); tbf with a filter.
fn (x &VindCtx) tb(it VindItem) int {
	return x.tbf(it, .none_)
}

fn (x &VindCtx) tbf(it VindItem, f VindFilter) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(false, -1, it.s, false, f, 0, 1))
}

// ta is getTokenAfter(item); taf with a filter, tas with a skip, tai with ITERATION_OPTS.
fn (x &VindCtx) ta(it VindItem) int {
	return x.taf(it, .none_)
}

fn (x &VindCtx) taf(it VindItem, f VindFilter) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(true, it.e, -1, false, f, 0, 1))
}

fn (x &VindCtx) tas(it VindItem, skip int) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(true, it.e, -1, false, .none_, skip, 1))
}

fn (x &VindCtx) tai(it VindItem) int {
	if !it.ok {
		return -1
	}
	return vind_one(x.st.cursor(true, it.e, -1, true, .not_ws, 0, 1))
}

// toks is getTokens(item); tokensf with a filter.
fn (x &VindCtx) toks(it VindItem) []int {
	return x.tokensf(it, .none_)
}

fn (x &VindCtx) tokensf(it VindItem, f VindFilter) []int {
	if !it.ok {
		return []
	}
	return x.st.cursor(true, it.s, it.e, false, f, 0, -1)
}

// between is getTokensBetween(left, right); betweenf with a filter.
fn (x &VindCtx) between(left VindItem, right VindItem) []int {
	return x.betweenf(left, right, .none_)
}

fn (x &VindCtx) betweenf(left VindItem, right VindItem, f VindFilter) []int {
	if !left.ok || !right.ok {
		return []
	}
	return x.st.cursor(true, left.e, right.s, false, f, 0, -1)
}

fn (x &VindCtx) is_punct(t int, v string) bool {
	return t >= 0 && vind_punct(&x.st.all[t], v)
}

fn (x &VindCtx) value(t int) string {
	return if t >= 0 { x.st.all[t].value } else { '' }
}

// ---------------------------------------------------------------------------------------------
// Offsets
// ---------------------------------------------------------------------------------------------

fn (x &VindCtx) info(t int) ?VindOff {
	if t < 0 || x.offs[t] < 0 {
		return none
	}
	return x.datas[x.offs[t]]
}

fn (mut x VindCtx) put(t int, o VindOff) {
	x.datas << o
	x.offs[t] = x.datas.len - 1
}

// set is setOffset of one token.
fn (mut x VindCtx) set(t int, offset int, base int) {
	if t < 0 || t == base {
		return
	}
	x.put(t, VindOff{
		base:   base
		offset: offset
	})
}

// sets is setOffset of a list of tokens.
fn (mut x VindCtx) sets(ts []int, offset int, base int) {
	for t in ts {
		x.set(t, offset, base)
	}
}

// copy_offset is copyOffset.
fn (mut x VindCtx) copy_offset(t int, src int) {
	if t < 0 {
		return
	}
	d := x.info(src) or { return }
	if t != d.base {
		x.put(t, VindOff{
			base:   d.base
			offset: d.offset
		})
	}
	if d.baseline {
		x.set_baseline(t)
	}
	if x.offs[t] >= 0 {
		x.datas[x.offs[t]].expected = d.expected
		x.datas[x.offs[t]].has_expected = d.has_expected
	}
}

fn (mut x VindCtx) set_baseline(t int) {
	if t >= 0 && x.offs[t] >= 0 {
		x.datas[x.offs[t]].baseline = true
	}
}

// first_last is getFirstAndLastTokens.
fn (x &VindCtx) first_last(it VindItem, border int) (int, int) {
	mut first := x.ft(it)
	mut last := x.lt(it)
	if first < 0 || last < 0 {
		return first, last
	}
	for {
		t := x.tb(x.titem(first))
		if t < 0 {
			break
		}
		u := x.ta(x.titem(last))
		if u < 0 {
			break
		}
		if !x.is_punct(t, '(') || !x.is_punct(u, ')') || x.st.all[t].us < border {
			break
		}
		first = t
		last = u
	}
	return first, last
}

fn (x &VindCtx) first_of(it VindItem) int {
	first, _ := x.first_last(it, 0)
	return first
}

// vind_beginning_of_line is isBeginningOfLine.
fn vind_beginning_of_line(nodes []VindItem, index int) bool {
	if !nodes[index].ok {
		return false
	}
	for i := index - 1; i >= 0; i-- {
		if !nodes[i].ok {
			continue
		}
		return nodes[index].sline != nodes[i].eline
	}
	return false
}

// node_list is processNodeList.
fn (mut x VindCtx) node_list(nodes []VindItem, left VindItem, right VindItem, offset int, align bool) {
	left_token := x.ft(left)
	right_token := x.ft(right)
	if nodes.len > 0 {
		mut base := -1
		mut last := left
		mut before_base := []int{}
		mut aligns := []int{}
		for node in nodes {
			if !node.ok {
				continue
			}
			first, last_token := x.first_last(node, if last.ok { last.e } else { 0 })
			if last.ok && first >= 0 {
				mut t := last
				for {
					n := x.tai(t)
					if n < 0 || x.st.all[n].ue > x.st.all[first].us {
						break
					}
					if base < 0 {
						before_base << n
					} else {
						aligns << n
					}
					t = x.titem(n)
				}
			}
			if base < 0 {
				base = first
			} else {
				aligns << first
			}
			last = x.titem(last_token)
		}
		if right_token >= 0 && last.ok {
			mut t := last
			for {
				n := x.tai(t)
				if n < 0 || x.st.all[n].ue > x.st.all[right_token].us {
					break
				}
				if base < 0 {
					before_base << n
				} else {
					aligns << n
				}
				t = x.titem(n)
			}
		}
		if left_token >= 0 {
			x.sets(before_base, offset, left_token)
		}
		if base >= 0 {
			if left_token >= 0 {
				x.set(base, offset, left_token)
			}
			for i in 0 .. nodes.len {
				if vind_beginning_of_line(nodes, i) {
					x.set_baseline(base)
					break
				}
			}
			if align || left_token < 0 {
				x.sets(aligns, 0, base)
			} else {
				x.sets(aligns, offset, left_token)
			}
		}
	}
	if right_token >= 0 && left_token >= 0 {
		x.set(right_token, 0, left_token)
	}
}

// maybe_block is processMaybeBlock.
fn (mut x VindCtx) maybe_block(node VindNode, base int) {
	first := x.first_of(x.item(node))
	x.set(first, if x.is_punct(first, '{') { 0 } else { 1 }, base)
}

// semicolons is processSemicolons.
fn (mut x VindCtx) semicolons(node VindNode) {
	it := x.item(node)
	first := x.ft(it)
	last := x.lt(it)
	if first != last && x.is_punct(last, ';') {
		x.set(last, 0, first)
	}
	if first < 0 || x.offs[first] < 0 {
		return
	}
	prev := x.tb(x.titem(first))
	if prev >= 0 && x.is_punct(prev, ';') && x.st.all[prev].end_line == x.st.all[first].line {
		x.offs[prev] = x.offs[first]
	}
}

// chain_head is getChainHeadToken.
fn (x &VindCtx) chain_head(node VindNode) int {
	typ := x.typ(node)
	mut n := node
	for {
		p := x.parent(n)
		if !p.ok() || x.typ(p) != typ {
			break
		}
		if x.is_punct(x.tb(x.item(n)), '(') {
			break
		}
		n = p
	}
	return x.ft(x.item(n))
}

fn (x &VindCtx) starts_at(t int, us int) bool {
	return t >= 0 && x.st.all[t].us == us
}

// beginning_of_element is isBeginningOfElement of indent-common.ts.
fn (x &VindCtx) beginning_of_element(token int, belonging VindNode) bool {
	tus := x.st.all[token].us
	mut node := belonging
	for node.ok() {
		parent := x.parent(node)
		if !parent.ok() {
			break
		}
		ptype := x.typ(parent)
		if ptype.ends_with('Statement') || ptype.ends_with('Declaration') {
			return x.item(parent).s == tus
		}
		if ptype == 'VExpressionContainer' {
			if x.item(node).s != tus {
				return false
			}
			return !x.is_punct(x.tb(x.item(belonging)), '(')
		}
		if ptype in ['CallExpression', 'NewExpression'] {
			open := x.taf(x.item(x.child(parent, .callee)), .not_close_paren)
			border := if open >= 0 { x.st.all[open].ue } else { 0 }
			for arg in x.list(parent, .arguments) {
				first, _ := x.first_last(x.item(arg), border)
				if x.starts_at(first, tus) {
					return true
				}
			}
			return false
		}
		if ptype == 'ArrayExpression' {
			for el in x.list(parent, .elements) {
				if el.ok() && x.starts_at(x.first_of(x.item(el)), tus) {
					return true
				}
			}
			return false
		}
		if ptype == 'SequenceExpression' {
			for e in x.list(parent, .expressions) {
				if x.starts_at(x.first_of(x.item(e)), tus) {
					return true
				}
			}
			return false
		}
		node = parent
	}
	return false
}

// top_level is processTopLevelNode.
fn (mut x VindCtx) top_level(node VindNode, expected int) {
	t := x.ft(x.item(node))
	if t < 0 {
		return
	}
	if x.offs[t] < 0 {
		x.put(t, VindOff{
			expected:     expected
			has_expected: true
		})
	} else {
		x.datas[x.offs[t]].expected = expected
		x.datas[x.offs[t]].has_expected = true
	}
}

// ignore ignores the tokens of the node.
fn (mut x VindCtx) ignore(node VindNode) {
	for t in x.toks(x.item(node)) {
		x.offs[t] = -1
		x.ignored[t] = true
	}
}

// ---------------------------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------------------------

struct VindExpected {
	indent int
	base   int
}

// expected_of is getExpectedIndents.
fn (x &VindCtx) expected_of(tokens []int) ?VindExpected {
	mut list := []int{}
	for i, t in tokens {
		info := x.info(t) or { continue }
		if !info.has_expected {
			base := x.info(info.base) or { continue }
			if base.has_expected && (i == 0 || !base.baseline) {
				list << base.expected + info.offset * x.opts.indent_size
				if base.baseline {
					break
				}
			}
		} else {
			list << info.expected
		}
	}
	if list.len == 0 {
		return none
	}
	mut min := list[0]
	for v in list {
		if v < min {
			min = v
		}
	}
	return VindExpected{list[0], min}
}

// indent_text is getIndentText.
fn (x &VindCtx) indent_text(t int) string {
	src := x.doc.src
	start := x.st.all[t].start
	mut i := start - 1
	for i >= 0 {
		b := src[i]
		if b == `\n` || b == `\r` {
			break
		}
		if (b == 0xa8 || b == 0xa9) && i >= 2 && src[i - 1] == 0x80 && src[i - 2] == 0xe2 {
			i -= 2
			break
		}
		i--
	}
	return src[i + 1..start]
}

// vind_json_char is JSON.stringify of a character of an indentation.
fn vind_json_char(r rune) string {
	return match r {
		`\t` { '"\\t"' }
		`\n` { '"\\n"' }
		`\r` { '"\\r"' }
		`\f` { '"\\f"' }
		`\b` { '"\\b"' }
		`"` { '"\\""' }
		`\\` { '"\\\\"' }
		else {
			if r < 0x20 { '"\\u${int(r):04x}"' } else { '"${r.str()}"' }
		}
	}
}

// vind_lt_at is the length of the line terminator at `i` (\n, \r, U+2028, U+2029), else 0.
fn vind_lt_at(s string, i int) int {
	if s[i] == `\n` || s[i] == `\r` {
		return 1
	}
	if s[i] == 0xe2 && i + 2 < s.len && s[i + 1] == 0x80 && (s[i + 2] == 0xa8 || s[i + 2] == 0xa9) {
		return 3
	}
	return 0
}

// vind_lines is `text.match(LINES) || []`: the lines of the text with their terminators, the
// empty ones left out.
fn vind_lines(text string) []string {
	mut out := []string{}
	mut i := 0
	for i < text.len {
		n := vind_lt_at(text, i)
		if n > 0 {
			i += n
			continue
		}
		start := i
		for i < text.len && vind_lt_at(text, i) == 0 {
			i++
		}
		if i < text.len {
			i += if text[i] == `\r` && i + 1 < text.len && text[i + 1] == `\n` {
				2
			} else {
				vind_lt_at(text, i)
			}
		}
		out << text[start..i]
	}
	return out
}

// vind_comment_prefix_len is the length of the match of /^\s*\*/ in the line, or -1.
fn vind_comment_prefix_len(line string) int {
	mut bytes := 0
	for r in line.runes() {
		if is_js_space(r) || r in [`\n`, `\r`, ` `, ` `] {
			bytes += r.length_in_bytes()
			continue
		}
		return if r == `*` { bytes + 1 } else { -1 }
	}
	return -1
}

// fix is defineFix.
fn (x &VindCtx) fix(t int, actual int, expected int) Fix {
	tok := &x.st.all[t]
	indent := [x.opts.indent_char].bytestr().repeat(expected)
	start := x.doc.byte_offset(tok.us - actual)
	if tok.typ == 'Block' && tok.line != tok.end_line {
		mut lines := vind_lines(x.doc.src[tok.start..tok.end])
		first := if lines.len > 0 { lines[0] } else { 'undefined' }
		if lines.len > 0 {
			lines.delete(0)
		}
		if lines.all(vind_comment_prefix_len(it) >= 0) {
			mut text := indent + first
			for l in lines {
				text += indent + ' *' + l[vind_comment_prefix_len(l)..]
			}
			return Fix{
				start: start
				end:   tok.end
				text:  text
			}
		}
	}
	return Fix{
		start: start
		end:   tok.start
		text:  indent
	}
}

fn (x &VindCtx) report(t int, text string, column int, end_column int, actual int, expected int) Finding {
	tok := &x.st.all[t]
	return Finding{
		stmt:             Ident{
			start_byte: tok.start
			end_byte:   tok.start
		}
		text:             text
		line_loc:         true
		fixed_line:       tok.line
		fixed_column:     column + 1
		fixed_end_line:   tok.line
		fixed_end_column: end_column + 1
		has_fix:          true
		fix:              x.fix(t, actual, expected)
	}
}

// validate_core is validateCore.
fn (mut x VindCtx) validate_core(t int, expected int, optional []int) {
	text := x.indent_text(t)
	if !vind_blank(text) {
		return
	}
	actual := x.st.all[t].column
	unit := if x.opts.indent_char == `\t` { 'tab' } else { 'space' }
	for i, r in text.runes() {
		if r != rune(x.opts.indent_char) {
			msg := vind_unexpected_char.replace('{{expected}}', vind_json_char(rune(x.opts.indent_char))).replace('{{actual}}',
				vind_json_char(r))
			x.findings << x.report(t, msg, i, i + 1, actual, expected)
			return
		}
	}
	if actual != expected && actual !in optional {
		msg := vind_unexpected_indentation.replace('{{expectedIndent}}', expected.str()).replace('{{actualIndent}}',
			actual.str()).replace('{{unit}}', unit).replace('{{expectedIndentPlural}}',
			if expected == 1 { '' } else { 's' }).replace('{{actualIndentPlural}}', if actual == 1 {
			''
		} else {
			's'
		})
		x.findings << x.report(t, msg, 0, actual, actual, expected)
	}
}

fn (x &VindCtx) is_closing(t int) bool {
	tok := &x.st.all[t]
	return tok.typ == 'HTMLEndTagOpen' || tok.typ == 'VExpressionEnd'
		|| (tok.typ == 'Punctuator' && tok.value in [')', '}', ']'])
}

// validate is validate of indent-common.ts.
fn (mut x VindCtx) validate(tokens []int, comments []int, last int) {
	first := tokens[0]
	actual := x.st.all[first].column
	exp := x.expected_of(tokens) or { return }
	mut baseline := map[int]bool{}
	for t in tokens {
		if x.offs[t] < 0 {
			continue
		}
		d := x.offs[t]
		if x.datas[d].baseline {
			x.datas[d].expected = if x.opts.indent_char == ` ` {
				math.max(0, x.st.all[t].column + exp.base - actual)
			} else {
				exp.base + if t == tokens[0] { 0 } else { 1 }
			}
			x.datas[d].has_expected = true
			baseline[t] = true
		} else if x.datas[d].base >= 0 && x.datas[d].base in baseline {
			b := x.info(x.datas[d].base) or { VindOff{} }
			x.datas[d].expected = b.expected
			x.datas[d].has_expected = b.has_expected
			baseline[t] = true
		} else {
			x.datas[d].expected = exp.base
			x.datas[d].has_expected = true
		}
	}
	if x.ignored[first] {
		return
	}
	mut optional := [exp.indent]
	if last >= 0 && x.is_closing(first) {
		if info := x.info(last) {
			if info.has_expected {
				indent := if exp.indent == info.expected {
					exp.indent + x.opts.indent_size
				} else {
					info.expected
				}
				optional = [indent, exp.indent]
			}
		}
	}
	for comment in comments {
		comment_expected := if e := x.expected_of([comment]) { e.indent } else { optional[0] }
		x.validate_core(comment, comment_expected, optional)
	}
	x.validate_core(first, exp.indent, [])
}

// check_lines is the `:matches(Program, VElement[parent.type!='VElement']):exit` listener: the
// validation of the lines of the top-level node.
fn (mut x VindCtx) check_lines(node VindNode) {
	it := x.item(node)
	mut comments := []int{}
	mut same_line := []int{}
	mut beside_multiline := false
	mut last_validated := -1
	for t in x.st.cursor(true, it.s, it.e, true, .not_ws, 0, -1) {
		line := x.st.all[t].line
		if same_line.len == 0 || x.st.all[same_line[0]].line == line {
			same_line << t
		} else if same_line.all(vind_is_comment(&x.st.all[it])) {
			comments << same_line[0]
			beside_multiline = x.st.all[same_line.last()].end_line == line
			same_line = [t]
		} else {
			if !beside_multiline {
				x.validate(same_line, comments, last_validated)
				last_validated = same_line[0]
			}
			beside_multiline = x.st.all[same_line.last()].end_line == line
			same_line = [t]
			comments = []
		}
	}
	if same_line.any(!vind_is_comment(&x.st.all[it])) {
		x.validate(same_line, comments, last_validated)
	}
}

// ---------------------------------------------------------------------------------------------
// The traversal
// ---------------------------------------------------------------------------------------------

// vind_is_expression is esquery's `:expression` class (with ESLint's matchesSelectorClass).
fn vind_is_expression(typ string, parent_type string) bool {
	return typ.ends_with('Expression') || typ.ends_with('Literal')
		|| (typ == 'Identifier' && parent_type != 'MetaProperty') || typ == 'MetaProperty'
}

fn vind_is_statement(typ string) bool {
	return typ.ends_with('Statement') || typ.ends_with('Declaration')
}

// vind_ts_semicolon_types are the types of indent-ts.ts's `processSemicolons` listener.
const vind_ts_semicolon_types = ['TSTypeAliasDeclaration', 'TSCallSignatureDeclaration',
	'TSConstructSignatureDeclaration', 'TSImportEqualsDeclaration', 'TSAbstractMethodDefinition',
	'TSAbstractPropertyDefinition', 'TSAbstractAccessorProperty', 'TSEnumMember', 'TSPropertySignature',
	'TSIndexSignature', 'TSMethodSignature', 'ClassProperty', 'TSAbstractClassProperty']

// vind_ts_member_types are the types of indent-ts.ts's listener of abstract members, enum
// members and class properties (6 identifiers: it runs before the semicolons' 13).
const vind_ts_member_types = ['TSAbstractMethodDefinition', 'TSAbstractPropertyDefinition',
	'TSAbstractAccessorProperty', 'TSEnumMember', 'ClassProperty', 'TSAbstractClassProperty']

// enter runs the listeners of a node being entered, in the order of their specificity:
// `:expression` (0 attributes, 0 identifiers), `:statement, PropertyDefinition` (0, 1; `:` sorts
// before the letters), the listener of the node's own type (0, 1, or 0, n for one of n types: the
// TS semicolons' 13 types come after the others), `*[type=/^TS/]` (1, 0), the top-level element
// (1, 1) and the TypeScript class listener (6, 6; `[implements]` matches any class of
// typescript-estree, which always has the array).
fn (mut x VindCtx) enter(n VindNode, typ string, ptype string) {
	if vind_is_expression(typ, ptype) {
		x.on_expression(n)
	}
	if vind_is_statement(typ) || typ == 'PropertyDefinition' {
		x.semicolons(n)
	}
	if typ in vind_ts_member_types {
		x.ts_member(n, typ)
		x.semicolons(n)
	} else {
		x.visit_type(n, typ)
		if typ in vind_ts_semicolon_types {
			x.semicolons(n)
		}
	}
	if typ.starts_with('TS') {
		x.ts_type_parens(n, ptype)
	}
	if typ == 'VElement' && ptype != 'VElement' {
		x.top_level(n, 0)
	}
	if typ in ['ClassDeclaration', 'ClassExpression'] {
		x.ts_class(n)
	}
}

const vind_validation_selector = esquery.parse_eslint(":matches(Program, VElement[parent.type!='VElement']):exit") or {
	panic(err)
}

// leave runs the `:exit` listeners: the one that ignores the tokens of the unknown nodes
// (`*:exit`, 0 attributes and identifiers), those of the `ignores` (sorted, before or after the
// validation of a top-level node by their specificity).
fn (mut x VindCtx) leave(n VindNode, typ string, ptype string, ignores []esquery.EslintSelector, ancestry []VindNode) ! {
	if !vind_known[typ] {
		x.ignore(n)
	}
	top := typ == 'Program' || (typ == 'VElement' && ptype != 'VElement')
	mut validated := false
	for sel in ignores {
		if top && !validated && sel.compare(&vind_validation_selector) > 0 {
			validated = true
			x.check_lines(n)
		}
		if x.ignore_matches(sel, n, typ, ancestry)! {
			x.ignore(n)
		}
	}
	if top && !validated {
		x.check_lines(n)
	}
}

// ignore_matches: an `ignores` selector matches the node being left. A plain type (or `*`)
// matches any node of that type; another selector is tried on the ESTree nodes, with their
// ESTree ancestors (a selector across the V* nodes of the template does not match).
fn (x &VindCtx) ignore_matches(sel esquery.EslintSelector, n VindNode, typ string, ancestry []VindNode) !bool {
	match sel.root.kind {
		.wildcard {
			return true
		}
		.identifier {
			return sel.root.value.to_lower() == typ.to_lower()
		}
		else {}
	}
	if n.es < 0 {
		return false
	}
	if types := sel.node_types {
		if typ !in types {
			return false
		}
	}
	mut list := []int{}
	for k := ancestry.len - 1; k >= 0; k-- {
		a := ancestry[k]
		if a.es < 0 || a.sn != n.sn {
			break
		}
		list << a.es
	}
	return esquery.matches(x.tree(n.sn), n.es, &sel.root, list)!
}

// run walks the traversal's events (`leaves[k]`: the event k leaves its node).
fn (mut x VindCtx) run(steps []VindNode, leaves []bool, ignores []esquery.EslintSelector) ! {
	mut stack := []VindNode{}
	for k, n in steps {
		typ := x.typ(n)
		if !leaves[k] {
			parent := if stack.len > 0 { stack.last() } else { x.parent(n) }
			if n.es >= 0 && n.sn >= 0 && parent.ok() {
				x.parents[n.key()] = parent
			}
			x.enter(n, typ, x.typ(parent))
			stack << n
			continue
		}
		stack.delete_last()
		parent := if stack.len > 0 { stack.last() } else { x.parent(n) }
		x.leave(n, typ, x.typ(parent), ignores, stack)!
	}
}

fn new_vind_ctx(doc &vue.Document, opts VindOptions, st VindStore) &VindCtx {
	return &VindCtx{
		doc:     doc
		opts:    opts
		st:      st
		offs:    []int{len: st.all.len, init: -1}
		ignored: []bool{len: st.all.len}
	}
}

fn vind_parse_ignores(patterns []string) ![]esquery.EslintSelector {
	mut out := []esquery.EslintSelector{}
	for p in patterns {
		out << esquery.parse_eslint('${p}:exit')!
	}
	out.sort_with_compare(fn (a &esquery.EslintSelector, b &esquery.EslintSelector) int {
		return a.compare(b)
	})
	return out
}

// lint_vue_html_indent is vue/html-indent: the template of a .vue file.
fn (mut c Checker) lint_vue_html_indent(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vind_options(c.rule_options(vue_html_indent), 1)
	ignores := vind_parse_ignores(opts.ignores)!
	doc := c.vue.doc
	mut x := new_vind_ctx(doc, opts, new_vind_store(doc, doc.tokens, doc.comments, false))
	mut steps := []VindNode{}
	mut leaves := []bool{}
	for step in c.vue_template_steps() {
		n := step.node
		steps << match n.kind {
			.vnode {
				VindNode{
					v: n.v
				}
			}
			.filter_callee {
				VindNode{
					v:      n.v
					callee: true
				}
			}
			.estree {
				VindNode{
					sn: n.snippet
					es: n.es
				}
			}
		}
		leaves << step.leave
	}
	x.run(steps, leaves, ignores)!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return x.findings
}

// lint_vue_script_indent is vue/script-indent: the <script> of a .vue file (its Program, as
// vue-eslint-parser gives it).
fn (mut c Checker) lint_vue_script_indent(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vind_options(c.rule_options(vue_script_indent), 0)
	ignores := vind_parse_ignores(opts.ignores)!
	tree := c.es_tree(root, abs_path) or { return [] }
	doc := c.vue.doc
	mut x := new_vind_ctx(doc, opts, new_vind_store(doc, doc.script.tokens, doc.script.comments,
		true))
	x.script = tree
	mut steps := []VindNode{}
	mut leaves := []bool{}
	for step in tree.steps() {
		steps << VindNode{
			es: step.node
		}
		leaves << step.leave
	}
	x.run(steps, leaves, ignores)!
	stats.checked++
	stats.eval_ms += ms(sw.elapsed())
	return x.findings
}
