module vue

import estree
import jsregexp
import treesitter

// ExprContext parses the code vue-eslint-parser hands to the script parser for template
// expressions (the port of src/script/index.ts and src/template/index.ts), and holds what that
// needs: the tree-sitter parsers and the token replacements to apply to the document.
struct ExprContext {
mut:
	doc     &Document = unsafe { nil }
	opts    Options
	ts      &C.TSParser = unsafe { nil }
	tsx     &C.TSParser = unsafe { nil }
	parsers &Parsers    = unsafe { nil }
	// tsx_mode: expressions are parsed with JSX (Options.fragment_jsx).
	tsx_mode bool
	// Replacements of the document's tokens (replaceTokens), applied in order by flush_tokens.
	replacements []Replacement
}

struct Replacement {
	start  int
	end    int
	tokens []Token
}

// ParseErr carries the ParseError of a failed parse.
struct ParseErr {
	Error
	perr ParseError
}

fn (e ParseErr) msg() string {
	return e.perr.message
}

fn parse_err(perr ParseError) IError {
	return IError(ParseErr{
		perr: perr
	})
}

fn new_expr_context(doc &Document, opts Options, parsers &Parsers) ExprContext {
	mut ctx := ExprContext{
		doc:     doc
		opts:    opts
		ts:      parsers.ts
		tsx:     parsers.tsx
		parsers: parsers
	}
	ctx.tsx_mode = opts.fragment_jsx
	return ctx
}

// Parsers are the tree-sitter parsers of the TypeScript grammar's two dialects, kept from file
// to file (making them is not free).
@[heap]
pub struct Parsers {
	ts  &C.TSParser = unsafe { nil }
	tsx &C.TSParser = unsafe { nil }
	// What may start and continue an identifier beyond ASCII (tree-sitter takes more).
	id_start    jsregexp.JsRegex
	id_continue jsregexp.JsRegex
}

pub fn new_parsers() !&Parsers {
	ts := C.ts_parser_new()
	tsx := C.ts_parser_new()
	if !C.ts_parser_set_language(ts, C.tree_sitter_typescript())
		|| !C.ts_parser_set_language(tsx, C.tree_sitter_tsx()) {
		C.ts_parser_delete(ts)
		C.ts_parser_delete(tsx)
		return error('the TypeScript grammar uses an ABI this tree-sitter runtime does not support')
	}
	return &Parsers{
		ts:          ts
		tsx:         tsx
		id_start:    jsregexp.js_regex_new('^[\\p{ID_Start}\$_]\$', 'u')!
		id_continue: jsregexp.js_regex_new('^[\\p{ID_Continue}\$\\u200C\\u200D]\$', 'u')!
	}
}

pub fn (p &Parsers) close() {
	C.ts_parser_delete(p.ts)
	C.ts_parser_delete(p.tsx)
}

// parse parses with the dialect's parser; the rows must be freed.
fn parse_ts(parser &C.TSParser, code string) !&C.vt_rows {
	return treesitter.parse_with(parser, code, 'a snippet')
}

// Fragment is a parsed snippet (parseScriptFragment): its program, tokens and comments, with file
// positions.
struct Fragment {
	snippet  int
	root     int
	tokens   []Token
	comments []Token
	// snip_start and snip_end are the ranges of the nodes in the snippet's code.
	snip_start []int
	snip_end   []int
}

// to_bytes converts a UTF-16 offset of the file to bytes.
@[inline]
fn (c &ExprContext) to_bytes(u int) int {
	return c.doc.index.to_byte(u)
}

// error_at makes a ParseError at a UTF-16 offset of the file.
fn (c &ExprContext) error_at(message string, u int) ParseError {
	return ParseError{
		message: message
		index:   c.to_bytes(u)
	}
}

// parse_fragment is parseScriptFragment: parses `code` (decoded text with a wrapper) and moves
// its nodes, tokens and comments to the file with `calc`.
fn (mut c ExprContext) parse_fragment(code string, calc Calc) !Fragment {
	tree := parse_ts(if c.tsx_mode { c.tsx } else { c.ts }, code)!
	root := treesitter.root_node(tree)
	code_index := new_text_index(code)
	// The file offset of each byte of the code (a byte inside a character: that character's
	// offset plus the byte's).
	u16_file := c.doc.offsets_with_gap(calc, code_index.u16_len)
	mut to_file := []int{len: code.len + 1}
	mut b := 0
	for b <= code.len {
		f := c.to_bytes(u16_file[code_index.to_u16(b)])
		n := if b < code.len { utf8_len(code[b]) } else { 1 }
		for k in 0 .. n {
			if b + k <= code.len {
				to_file[b + k] = f + k
			}
		}
		b += n
	}
	mut error_at := -1
	mut message := 'Parsing error.'
	mut toks := []SnipToken{}
	mut comms := []SnipToken{}
	if C.vt_node_has_error(root) {
		error_at = first_error_offset(root)
	} else {
		toks, comms = snippet_tokens(root, code, c.tsx_mode)
		if at, msg := reserved_identifier(toks, code) {
			error_at = at
			message = msg
		} else {
			bad := c.invalid_identifier_char(toks, code)
			if bad >= 0 {
				error_at = bad
				message = 'Invalid character.'
			}
		}
	}
	mut es := estree.EsTree{}
	if error_at < 0 {
		es = estree.convert_with(root, code, c.tsx_mode, estree.Options{
			module:       true
			regexp_valid: fn (pattern string, flags string) bool {
				return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
			}
		}) or {
			error_at = 0
			estree.EsTree{}
		}
	}
	if error_at >= 0 {
		// The message is TypeScript's diagnostic, which tree-sitter does not give: see
		// ParseError.ts_message.
		treesitter.rows_free(tree)
		c.doc.snippets << Snippet{
			code:    code
			tsx:     c.tsx_mode
			to_file: to_file
		}
		return parse_err(ParseError{
			message:    message
			index:      to_file[error_at]
			ts_message: true
			snippet:    c.doc.snippets.len - 1
		})
	}
	mut snip_start := []int{cap: es.nodes.len}
	mut snip_end := []int{cap: es.nodes.len}
	for node in es.nodes {
		snip_start << node.start
		snip_end << node.end
	}
	for mut node in es.nodes {
		node.start = to_file[node.start]
		node.end = to_file[node.end]
	}
	mut tokens := []Token{cap: toks.len}
	for t in toks {
		value := code[t.start..t.end]
		tokens << Token{
			typ:   t.typ
			start: to_file[t.start]
			end:   to_file[t.end]
			value: if t.typ == 'PrivateIdentifier' { value[1..] } else { value }
		}
	}
	mut comments := []Token{cap: comms.len}
	for t in comms {
		value := if t.typ == 'Block' {
			code[t.start + 2..t.end - 2]
		} else {
			code[t.start + 2..t.end]
		}
		comments << Token{
			typ:   t.typ
			start: to_file[t.start]
			end:   to_file[t.end]
			value: value
		}
	}
	c.doc.snippets << Snippet{
		code:    code
		tsx:     c.tsx_mode
		tree:    tree
		es:      es
		to_file: to_file
	}
	return Fragment{
		snippet:    c.doc.snippets.len - 1
		root:       es.root
		tokens:     tokens
		comments:   comments
		snip_start: snip_start
		snip_end:   snip_end
	}
}

// first_error_offset is where the first ERROR or MISSING node of the tree starts.
fn first_error_offset(root C.vt_node) int {
	first, last := treesitter.flat_range(root)
	mut i := first
	for i <= last {
		node := treesitter.flat_node(root, i)
		if C.vt_node_is_error(node) || C.vt_node_is_missing(node) {
			return treesitter.node_start(node)
		}
		// Only the subtrees with an error are entered.
		i = if C.vt_node_has_error(node) { i + 1 } else { treesitter.flat_last(root, i) + 1 }
	}
	return treesitter.node_start(root)
}

// Reserved words tree-sitter takes for identifiers where TypeScript's parser fails.
const reserved_words = ['break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default',
	'delete', 'do', 'else', 'enum', 'export', 'extends', 'finally', 'for', 'function', 'if', 'import',
	'in', 'instanceof', 'new', 'return', 'switch', 'throw', 'try', 'typeof', 'var', 'void', 'while',
	'with']

const reserved_set = build_set(reserved_words)

// Of those, the ones that start an expression for TypeScript: it fails at the next token.
const reserved_expression_starts = ['class', 'delete', 'function', 'import', 'new', 'typeof', 'void']

// reserved_identifier gives, for the first `identifier` token that is a reserved word, where
// TypeScript reports it and (roughly) its message.
fn reserved_identifier(tokens []SnipToken, code string) ?(int, string) {
	for t in tokens {
		if !t.reserved {
			continue
		}
		text := code[t.start..t.end]
		if text in reserved_expression_starts {
			return t.end + leading_space_len(code[t.end..]), 'Expression expected.'
		}
		parent := treesitter.node_parent(t.node) or { t.node }
		return t.start, if treesitter.node_kind(parent) == 'arguments' {
			'Argument expression expected.'
		} else {
			'Expression expected.'
		}
	}
	return none
}

// invalid_identifier_char is where a name has a character TypeScript does not take in an
// identifier (an emoji, U+FFFD of a NUL…), or -1.
fn (c &ExprContext) invalid_identifier_char(tokens []SnipToken, code string) int {
	for t in tokens {
		if t.typ != 'Identifier' && t.typ != 'PrivateIdentifier' {
			continue
		}
		mut ascii := true
		for i in t.start .. t.end {
			if code[i] >= 0x80 {
				ascii = false
				break
			}
		}
		if ascii {
			continue
		}
		mut i := t.start
		if t.typ == 'PrivateIdentifier' {
			i++
		}
		mut first := true
		for i < t.end {
			cp, n := decode_cp(code, i)
			if cp >= 0x80 {
				mut units := []u16{}
				jsregexp.append_utf16(mut units, cp)
				re := if first { &c.parsers.id_start } else { &c.parsers.id_continue }
				if !(re.test(units) or { true }) {
					return i
				}
			}
			first = false
			i += n
		}
	}
	return -1
}

// es is the EsTree of a snippet.
@[inline]
fn (c &ExprContext) es(snippet int) &estree.EsTree {
	return &c.doc.snippets[snippet].es
}

// simple_token is createSimpleToken with UTF-16 offsets of the file.
fn (c &ExprContext) simple_token(typ string, start int, end int, value string) Token {
	return Token{
		typ:   typ
		start: c.to_bytes(start)
		end:   c.to_bytes(end)
		value: value
	}
}

// flush_tokens applies the pending replacements of the document's tokens (replaceTokens: the
// tokens from the first that starts at the range's start to the last that ends at its end give
// way to the new ones). They come in document order, so one merge does it; otherwise they are
// spliced one by one, as the original does.
fn (mut c ExprContext) flush_tokens() {
	if c.replacements.len == 0 {
		return
	}
	old := c.doc.tokens
	mut extra := 0
	for r in c.replacements {
		extra += r.tokens.len
	}
	mut out := []Token{cap: old.len + extra}
	mut cur := 0
	mut ri := 0
	for ri < c.replacements.len {
		r := c.replacements[ri]
		if out.len > 0 && (out.last().start >= r.start || out.last().end > r.end) {
			break
		}
		mut index := cur
		mut hi := old.len
		for index < hi {
			mid := (index + hi) >> 1
			if old[mid].start < r.start {
				index = mid + 1
			} else {
				hi = mid
			}
		}
		mut last := cur
		hi = old.len
		for last < hi {
			mid := (last + hi) >> 1
			if old[mid].end <= r.end {
				last = mid + 1
			} else {
				hi = mid
			}
		}
		out << old[cur..index]
		out << r.tokens
		cur = if last > index { last } else { index }
		ri++
	}
	out << old[cur..]
	c.doc.tokens = out
	for ri < c.replacements.len {
		r := c.replacements[ri]
		c.doc.replace_tokens(r.start, r.end, r.tokens)
		ri++
	}
	c.replacements.clear()
}

// replace_tokens is replaceTokens on the document's tokens.
fn (mut d Document) replace_tokens(start int, end int, tokens []Token) {
	index := sorted_index_by_start(d.tokens, start)
	last := sorted_last_index_by_end(d.tokens, end)
	count := last - index
	if count > 0 {
		d.tokens.delete_many(index, count)
	}
	d.tokens.insert(index, tokens)
}

fn sorted_index_by_start(list []Token, value int) int {
	mut lo := 0
	mut hi := list.len
	for lo < hi {
		mid := (lo + hi) >> 1
		if list[mid].start < value {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

fn sorted_last_index_by_end(list []Token, value int) int {
	mut lo := 0
	mut hi := list.len
	for lo < hi {
		mid := (lo + hi) >> 1
		if list[mid].end <= value {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// insert_comments is insertComments.
fn (mut d Document) insert_comments(comments []Token) {
	if comments.len == 0 {
		return
	}
	index := sorted_index_by_start(d.comments, comments[0].start)
	d.comments.insert(index, comments)
}

// insert_error is insertError: before the first error whose index is not smaller.
fn (mut d Document) insert_error(err ParseError) {
	mut lo := 0
	mut hi := d.errors.len
	for lo < hi {
		mid := (lo + hi) >> 1
		if d.errors[mid].index < err.index {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	d.errors.insert(lo, err)
}
