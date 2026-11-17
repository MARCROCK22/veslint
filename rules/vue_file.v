module rules

import estree
import offsets
import treesitter { TokenEnds, token_ends }
import vue

// A .vue file is linted as ESLint lints it with vue-eslint-parser: the rules see the script as
// that parser gives it (the tree of the masked script, so the nodes have the positions of the
// file; the whole file as the source text; the script's tokens and comments), and the types come
// from tsgo, which has the code typescript-eslint type-checks for the script (ScriptInfo.code) in
// a virtual TypeScript twin of the file. The positions of the twin are not those of the file:
// every position veslint sends to tsgo, or gets from it, goes through the functions below, which
// are the identity for any other file.

// vue_twin_suffix makes the name of the twin of a .vue file: `App.vue.vls.ts`, a file TypeScript
// lints as TypeScript and that an `import './App.vue'` does not resolve to (TypeScript tries
// `App.vue.ts`, `App.vue.tsx`, `App.vue.d.ts` and `App.d.vue.ts`), so the other files keep seeing
// the `*.vue` shim, as they do in ESLint.
pub const vue_twin_suffix = '.vls.ts'

// is_vue_path: the file is a Vue SFC, linted through vue-eslint-parser's reading of it.
pub fn is_vue_path(path string) bool {
	return path.to_lower().ends_with('.vue')
}

// vue_twin_path is the path of the twin tsgo has for a .vue file.
pub fn vue_twin_path(abs_path string) string {
	return abs_path + vue_twin_suffix
}

// VueView is the .vue file the Checker lints (set_vue), with what maps its positions to the twin.
struct VueView {
mut:
	doc     &vue.Document = unsafe { nil }
	ts_path string // the twin, as tsgo knows it
	// code_ends are the ends of the tokens of the twin's text (bytes), sorted: where TypeScript's
	// nodes begin (their `pos` includes the leading trivia). Built on first use, per file.
	code_ends     []int
	has_code_ends bool
	// The traversal of the template (vue_template.v), built on first use.
	steps      []VueStep
	has_steps  bool
	vnodes     []int
	has_vnodes bool
}

// file_token_ends are the token ends of the tree (TokenEnds): for a .vue file, without the `;`
// the masked script has between two scripts (vue-eslint-parser drops it, and a statement that
// ends with it ends at the token before it).
fn (c &Checker) file_token_ends(root C.TSNode) TokenEnds {
	ends := token_ends(root)
	if !c.is_vue() || c.vue.doc.script.split_offsets.len == 0 {
		return ends
	}
	split := c.vue.doc.script.split_offsets
	return TokenEnds{
		ends: ends.ends.filter(it - 1 !in split)
	}
}

// set_vue makes the next lint_file lint `doc`, a parsed .vue file whose text is the one lint_file
// gets, and whose twin tsgo has at `ts_path`. lint_file forgets it when it returns.
pub fn (mut c Checker) set_vue(doc &vue.Document, ts_path string) {
	c.vue = VueView{
		doc:     doc
		ts_path: ts_path
	}
}

// is_vue: the file being linted is a .vue file.
fn (c &Checker) is_vue() bool {
	return c.vue.doc != unsafe { nil }
}

// is_typescript_file ports eslint-plugin-unicorn's isTypeScriptFile(context.physicalFilename): the
// name ends in .ts, .mts, .cts or .tsx, which every file veslint lints has but a .vue file.
fn (c &Checker) is_typescript_file() bool {
	return !c.is_vue()
}

// is_ts_script_kind: TypeScript reads the file as ScriptKind TS or TSX. A .vue file is of the
// kind TypeScript gives an extra extension (Deferred) in the project service, and TS in the
// programs typescript-eslint makes for `parserOptions.project`.
fn (c &Checker) is_ts_script_kind() bool {
	return !c.is_vue() || c.project_programs
}

// parse_text is the text tree-sitter parsed: the masked script of a .vue file (same length as the
// file), the source of any other.
fn (c &Checker) parse_text() string {
	return if c.is_vue() { c.vue.doc.script.masked } else { c.src }
}

// ts_text is the text tsgo has for the file being linted.
fn (c &Checker) ts_text() string {
	return if c.is_vue() { c.vue.doc.script.code } else { c.src }
}

// vue_code_ends are the token ends of the twin's text (see VueView).
fn (mut c Checker) vue_code_ends() []int {
	if !c.vue.has_code_ends {
		c.vue.code_ends = c.vue.doc.script.synthetic_token_ends(c.tokens.ends)
		c.vue.has_code_ends = true
	}
	return c.vue.code_ends
}

// ts_spans gives, for each pair (start, end) of byte offsets of the file (where a node's first
// token starts and where its range ends), the range TypeScript gives the node in the text tsgo
// has: `pos` is the end of the token before it, `end` the end of its last token, in UTF-16 units.
// A node the twin does not have gets -1.
fn (mut c Checker) ts_spans(pairs []int) []int {
	if !c.is_vue() {
		mut bytes := []int{cap: pairs.len}
		for i := 0; i + 1 < pairs.len; i += 2 {
			bytes << c.tokens.last_end(pairs[i])
			bytes << c.tokens.last_end(pairs[i + 1])
		}
		return offsets.utf16_offsets(c.src, bytes)
	}
	ends := c.vue_code_ends()
	script := &c.vue.doc.script
	mut bytes := []int{cap: pairs.len}
	for i := 0; i + 1 < pairs.len; i += 2 {
		start := script.file_to_synthetic(pairs[i], false)
		end := script.file_to_synthetic(c.tokens.last_end(pairs[i + 1]), true)
		if start < 0 || end < 0 {
			bytes << -1
			bytes << -1
			continue
		}
		bytes << last_end_in(ends, start)
		bytes << end
	}
	return c.code_units(bytes)
}

// ts_offsets converts byte offsets of the file to UTF-16 offsets of the text tsgo has (-1 for an
// offset the twin does not have).
fn (c &Checker) ts_offsets(bytes []int) []int {
	if !c.is_vue() {
		return offsets.utf16_offsets(c.src, bytes)
	}
	script := &c.vue.doc.script
	return c.code_units(bytes.map(script.file_to_synthetic(it, false)))
}

// code_units converts byte offsets of the twin's text to UTF-16 ones, -1 staying -1.
fn (c &Checker) code_units(bytes []int) []int {
	code := c.vue.doc.script.code
	units := offsets.utf16_offsets(code, bytes.map(if it < 0 { 0 } else { it }))
	mut out := []int{len: bytes.len}
	for i, b in bytes {
		out[i] = if b < 0 { -1 } else { units[i] }
	}
	return out
}

// file_offset_of_ts_unit converts a UTF-16 offset of the text tsgo has (a TypeScript position) to
// a byte offset of the file.
fn (c &Checker) file_offset_of_ts_unit(unit int) int {
	if !c.is_vue() {
		return offsets.byte_offset(c.src, unit)
	}
	return c.file_offset_of_ts_byte(offsets.byte_offset(c.vue.doc.script.code, unit))
}

// file_offset_of_ts_byte converts a byte offset of the text tsgo has to a byte offset of the
// file, as vue-eslint-parser moves the positions typescript-estree gives.
fn (c &Checker) file_offset_of_ts_byte(b int) int {
	if !c.is_vue() {
		return b
	}
	return c.vue.doc.script.synthetic_to_file(b, false)
}

// file_offset_of_ts_end is file_offset_of_ts_byte for the end of a range.
fn (c &Checker) file_offset_of_ts_end(b int) int {
	if !c.is_vue() {
		return b
	}
	return c.vue.doc.script.synthetic_to_file(b, true)
}

// vue_es_tree takes the ESTree of a .vue file from its document, which converted it from the same
// tree, as vue-eslint-parser gives it: the Program has the range of the script (not the file's),
// and the source text is the whole file.
fn (mut c Checker) vue_es_tree(root C.TSNode) {
	script := &c.vue.doc.script
	source := if script.has_es {
		script.es
	} else if script.tree == unsafe { nil } {
		// No script, or an empty one: lint_file parsed the masked file, which has no code.
		estree.convert_with(root, script.masked, false, estree.Options{ module: true }) or {
			c.file_es_state = .failed
			return
		}
	} else {
		// A script with syntax errors.
		c.file_es_state = .failed
		return
	}
	// The lines of vue-eslint-parser's locations end only at a line feed.
	mut line_units := [0]
	line_units << c.vue.doc.line_terminators
	mut tree := estree.EsTree{
		...source
		nodes:       source.nodes.clone()
		src:         c.src
		line_starts: c.vue.doc.line_starts.clone()
		line_units:  line_units
	}
	tree.nodes[tree.root].start = script.program_start
	tree.nodes[tree.root].end = script.program_end
	c.file_es = tree
	c.file_es_state = .built
}

// vue_tag_tokens gives the tokens of a .vue file as vue-eslint-parser has them: without the `;`
// the masked script has between two scripts, and with the `<script>` and `</script>` punctuators
// it puts among them, one for each tag of the scripts (their range is the tag's): ESLint's token
// queries find them before the first token of the script and after its last one.
fn (c &Checker) vue_tag_tokens(tokens &SourceTokens, root C.TSNode) &SourceTokens {
	script := &c.vue.doc.script
	tags := script.tokens.filter(it.typ == 'Punctuator' && it.value in ['<script>', '</script>'])
	if tags.len == 0 && script.split_offsets.len == 0 {
		return tokens
	}
	mut all := tokens.all.filter(it.start !in script.split_offsets)
	mut only := tokens.tokens.filter(it.start !in script.split_offsets)
	for tag in tags {
		token := SourceToken{
			start: tag.start
			end:   tag.end
			kind:  .punctuator
			node:  root
		}
		all.insert(source_tokens_index(all, tag.start), token)
		only.insert(source_tokens_index(only, tag.start), token)
	}
	return &SourceTokens{
		tokens:   only
		comments: tokens.comments
		all:      all
	}
}

// last_end_in is TokenEnds.last_end on a sorted list of ends: the last one at or before `offset`.
fn last_end_in(ends []int, offset int) int {
	mut lo := 0
	mut hi := ends.len
	for lo < hi {
		mid := (lo + hi) / 2
		if ends[mid] <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return if lo == 0 { 0 } else { ends[lo - 1] }
}
