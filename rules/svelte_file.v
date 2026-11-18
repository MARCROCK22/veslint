module rules

import estree
import offsets
import treesitter { node_field, node_kind, node_parent, node_start }
import svelte
import tsgo

// A .svelte file is linted as ESLint lints it with svelte-eslint-parser and typescript-eslint's
// parser: the rules see the script and the template's expressions in one Program. veslint's
// rules parse the document's lint code (svelte/lint.v): the script at the file's offsets, then
// each template expression in a neutral wrapper statement. Their source text is the file
// followed by that template part (Document.lint_text), so a node's text is its text in the
// file. Positions of the tree are offsets of the lint code: a report is moved to the file
// (Document.lint_to_file) when lint_file ends, and dropped when it is on a wrapper's character.
// The types come from tsgo, which has the virtual code svelte-eslint-parser gives
// typescript-eslint (Document.virtual_code) in a virtual twin of the file: every position sent
// to tsgo, or got from it, goes through the functions below (the lint code to the file, the file
// to the virtual code), as for a .vue file (vue_file.v).

// is_svelte_path: the file is a Svelte component, linted through svelte-eslint-parser's reading
// of it. A `.svelte.ts` module is a TypeScript file (its name ends in .ts).
pub fn is_svelte_path(path string) bool {
	return path.to_lower().ends_with('.svelte')
}

// svelte_twin_path is the path of the twin tsgo has for a .svelte file: `App.svelte.vls.ts`, a
// TypeScript file that `import './App.svelte'` does not resolve to (TypeScript tries
// `App.svelte.ts`, `.tsx`, `.d.ts` and `App.d.svelte.ts`), so the other files keep the
// `*.svelte` module declaration, as in ESLint.
pub fn svelte_twin_path(abs_path string) string {
	return abs_path + vue_twin_suffix
}

// SvelteView is the .svelte file the Checker lints (set_svelte).
struct SvelteView {
mut:
	doc     &svelte.Document = unsafe { nil }
	ts_path string // the twin, as tsgo knows it
	parsers &svelte.Parsers = unsafe { nil }
	// code_ends are the ends of the tokens of the virtual code (UTF-16), sorted: where
	// TypeScript's nodes begin. Built on first use.
	code_ends     []int
	has_code_ends bool
}

// set_svelte makes the next lint_file lint `doc`, a parsed .svelte file whose text is the one
// lint_file gets, and whose twin tsgo has at `ts_path`; `parsers` parse its virtual code when
// the types are asked. lint_file forgets it when it returns.
pub fn (mut c Checker) set_svelte(doc &svelte.Document, ts_path string, parsers &svelte.Parsers) {
	c.svelte = SvelteView{
		doc:     doc
		ts_path: ts_path
		parsers: parsers
	}
}

// is_svelte: the file being linted is a .svelte file.
fn (c &Checker) is_svelte() bool {
	return c.svelte.doc != unsafe { nil }
}

// svelte_code_ends are the token ends of the virtual code (see SvelteView).
fn (mut c Checker) svelte_code_ends() []int {
	if !c.svelte.has_code_ends {
		c.svelte.has_code_ends = true
		code := c.svelte.doc.virtual_code
		if c.svelte.parsers != unsafe { nil } {
			ends := c.svelte.parsers.token_ends(code) or { []int{} }
			c.svelte.code_ends = offsets.utf16_offsets(code, ends)
		}
	}
	return c.svelte.code_ends
}

// svelte_file_to_lint maps a byte offset of the file to the lint code: the same in the script,
// the first copy of it among the template expressions; -1 elsewhere.
fn (c &Checker) svelte_file_to_lint(offset int, end bool) int {
	doc := c.svelte.doc
	if offset < 0 {
		return -1
	}
	if offset < doc.lint_start && offset < doc.src.len && offset < doc.lint_code.len
		&& doc.lint_code[offset] == doc.src[offset] {
		return offset
	}
	for s in doc.lint_segments {
		if s.file_start <= offset && (offset < s.file_start + s.len
			|| (end && offset == s.file_start + s.len)) {
			return s.pre_start + offset - s.file_start
		}
	}
	if end && offset > 0 && offset <= doc.src.len && offset - 1 < doc.lint_code.len
		&& doc.lint_code[offset - 1] == doc.src[offset - 1] {
		return offset
	}
	return -1
}

// svelte_virtual_start is where TypeScript sees the character at a byte offset of the lint code
// (UTF-16 offset of the virtual code), or -1.
fn (c &Checker) svelte_virtual_start(offset int) int {
	file := c.svelte.doc.lint_to_file(offset, false)
	if file < 0 {
		return -1
	}
	return c.svelte.doc.file_to_virtual(file)
}

// svelte_virtual_end is where TypeScript sees the end of a range ending at a byte offset of the
// lint code: after its last character.
fn (c &Checker) svelte_virtual_end(offset int) int {
	doc := c.svelte.doc
	file := doc.lint_to_file(offset, true)
	if file <= 0 {
		return -1
	}
	mut last := file - 1
	for last > 0 && doc.src[last] & 0xc0 == 0x80 {
		last--
	}
	start := doc.file_to_virtual(last)
	if start < 0 {
		return -1
	}
	piece := doc.src[last..file]
	return start + offsets.utf16_offsets(piece, [piece.len])[0]
}

// svelte_ts_spans is ts_spans for a .svelte file.
fn (mut c Checker) svelte_ts_spans(pairs []int) []int {
	ends := c.svelte_code_ends()
	mut out := []int{cap: pairs.len}
	for i := 0; i + 1 < pairs.len; i += 2 {
		start := c.svelte_virtual_start(pairs[i])
		end := c.svelte_virtual_end(c.tokens.last_end(pairs[i + 1]))
		if start < 0 || end < 0 {
			out << -1
			out << -1
			continue
		}
		out << last_end_in(ends, start)
		out << end
	}
	return out
}

// svelte_lint_offset_of_ts_unit maps a UTF-16 offset of the virtual code to the lint code.
fn (c &Checker) svelte_lint_offset_of_ts_unit(unit int, end bool) int {
	file := c.svelte.doc.virtual_to_file(unit, end)
	return c.svelte_file_to_lint(file, end)
}

// svelte_es_tree is es_tree for a .svelte file: the ESTree of the lint tree.
fn (mut c Checker) svelte_es_tree(top C.TSNode) {
	tree := estree.convert_with(top, c.src, false, estree.Options{
		module: true
	}) or {
		c.file_es_state = .failed
		return
	}
	c.file_es = tree
	c.file_es_state = .built
}

// svelte_move_findings moves the findings of the lint tree to the file: a report that starts on a
// wrapper's character is not ESLint's (it has no such node), nor is a fix that touches one; a
// report the file part already has (a rule that reads the text read the template's copy too)
// is kept once.
fn (c &Checker) svelte_move_findings(findings []Finding) []Finding {
	doc := c.svelte.doc
	mut out := []Finding{cap: findings.len}
	mut seen := map[string]bool{}
	for f in findings {
		start := if f.stmt.row < 0 {
			f.stmt.start_byte
		} else {
			doc.lint_to_file(f.stmt.start_byte, false)
		}
		if start < 0 {
			continue
		}
		end := if f.stmt.end_byte < 0 { -1 } else { doc.lint_end_to_file(f.stmt.end_byte) }
		mut fix := f.fix
		mut has_fix := f.has_fix
		if has_fix {
			fix = svelte_move_fix(doc, f.fix) or {
				has_fix = false
				Fix{}
			}
		}
		mut suggestions := []Suggestion{cap: f.suggestions.len}
		for s in f.suggestions {
			moved := svelte_move_fix(doc, s.fix) or { continue }
			suggestions << Suggestion{
				...s
				fix: moved
			}
		}
		moved := Finding{
			...f
			stmt:        treesitter.Ident{
				...f.stmt
				start_byte: start
				end_byte:   if end >= start { end } else { -1 }
			}
			has_fix:     has_fix
			fix:         fix
			suggestions: suggestions
		}
		key := '${moved.rule}\x00${start}\x00${moved.stmt.end_byte}\x00${moved.message_id}\x00${moved.text}\x00${moved.data}'
		if key in seen {
			continue
		}
		seen[key] = true
		out << moved
	}
	return out
}

// svelte_move_fix moves a fix of the lint code to the file; none when it touches a wrapper.
fn svelte_move_fix(doc &svelte.Document, fix Fix) ?Fix {
	if fix.end == fix.start {
		// An insertion: after a character of the file, or before one.
		mut at := doc.lint_to_file(fix.start, true)
		if at < 0 {
			at = doc.lint_to_file(fix.start, false)
		}
		if at < 0 {
			return none
		}
		return Fix{
			...fix
			start: at
			end:   at
		}
	}
	start := doc.lint_to_file(fix.start, false)
	end := doc.lint_to_file(fix.end, true)
	// A range across two pieces of the lint code is not one of the file.
	if start < 0 || end < 0 || end - start != fix.end - fix.start {
		return none
	}
	return Fix{
		...fix
		start: start
		end:   end
	}
}

// svelte_parsing_error is ESLint's fatal problem for a .svelte file svelte-eslint-parser rejects
// (`Parsing error: <message>`, at the error's line and 0-based column): a compiler error or one of
// the converter at its offset of the file; a TypeScript error of the script at TypeScript's first
// syntactic diagnostic of the pre-virtual code, in that code's lines (typescript-estree throws it
// from the parse of that code).
fn (mut c Checker) svelte_parsing_error() []Finding {
	doc := c.svelte.doc
	e := doc.error or { return [] }
	mut message := e.message
	mut line := 0
	mut column := 0
	if e.ts_message {
		diagnostics := c.client.transpile_diagnostics(doc.pre_u16, 'file.ts') or {
			[]tsgo.Diagnostic{}
		}
		if diagnostics.len > 0 {
			message = diagnostics[0].text
			line, column = ts_line_and_character(doc.pre_u16, diagnostics[0].pos)
		} else {
			line, column = ts_line_and_character(doc.pre_u16, offsets.utf16_offsets(doc.pre,
				[if e.pre_index >= 0 { e.pre_index } else { 0 }])[0])
		}
	} else {
		loc := doc.loc(e.index)
		line, column = loc.line, loc.column
	}
	return [
		Finding{
			stmt:             treesitter.Ident{
				start_byte: 0
			}
			rule:             problem_rule
			message_id:       'fatal'
			text:             'Parsing error: ${message}'
			column_from_zero: true
			fixed_line:       line
			fixed_column:     column + 1
		},
	]
}

// ts_line_and_character is TypeScript's getLineAndCharacterOfPosition of a UTF-16 offset of a
// text: the line from 1 (lines end at CR, LF, CRLF, U+2028 and U+2029) and the character from 0.
fn ts_line_and_character(text string, unit int) (int, int) {
	mut line := 1
	mut line_start := 0
	mut u := 0
	runes := text.runes()
	for i := 0; i < runes.len && u < unit; i++ {
		r := runes[i]
		width := if r > 0xffff { 2 } else { 1 }
		if r == `\r` && i + 1 < runes.len && runes[i + 1] == `\n` {
			u++
			continue
		}
		u += width
		if r in [`\n`, `\r`, rune(0x2028), rune(0x2029)] {
			line++
			line_start = u
		}
	}
	return line, unit - line_start
}

// is_svelte_reactive_statement: a top-level `$:` statement of a .svelte file's script, which is a
// SvelteReactiveStatement for ESLint, not a LabeledStatement (the rules about labels skip it).
fn (c &Checker) is_svelte_reactive_statement(n C.TSNode) bool {
	if !c.is_svelte() || node_kind(n) != 'labeled_statement'
		|| node_start(n) >= c.svelte.doc.lint_start {
		return false
	}
	label := node_field(n, 'label') or { return false }
	parent := node_parent(n) or { return false }
	return c.text(label) == '\$' && node_kind(parent) == 'program'
}

// file_text is the text of the file: for a .svelte file, the source text without the template
// part of the lint code (what the rules that read the text, not the nodes, look at).
fn (c &Checker) file_text() string {
	if c.is_svelte() {
		return c.src[..c.svelte.doc.src.len]
	}
	return c.src
}

// svelte_binding_assignment: the assignment is the lint code's wrapper of a `bind:` directive's
// name (`[(name)+=0];`), not an assignment of the file: its right side is the wrapper's.
fn (c &Checker) svelte_binding_assignment(t &estree.EsTree, node int) bool {
	if !c.is_svelte() || t.nodes[node].start < c.svelte.doc.lint_start {
		return false
	}
	right := t.node(node, .right) or { return false }
	return c.svelte.doc.lint_to_file(t.nodes[right].start, false) < 0
}

// svelte_function_shape_rules are the rules that check what a function looks like (its
// parameters, its parentheses): the lint code's functions of {#each}, let:, {:then}, {:catch} and
// {#snippet} are not functions for ESLint (their parameters belong to a Svelte block), so their
// reports on those functions' heads are not ESLint's. The rules that look at the scopes (unused or
// shadowed variables) keep theirs, as ESLint's scopes have those parameters.
const svelte_function_shape_rules = [prefer_readonly_parameter_types, stylistic_space_before_function_paren,
	stylistic_function_paren_newline]

// svelte_drop_wrapper_function_findings drops what svelte_function_shape_rules report in the
// head (from its start to its body) of a function of the template part that is a wrapper.
fn (mut c Checker) svelte_drop_wrapper_function_findings(root C.TSNode, findings []Finding) []Finding {
	if !findings.any(it.rule in svelte_function_shape_rules) {
		return findings
	}
	doc := c.svelte.doc
	mut heads := [][2]int{}
	for f in c.nodes_of_kinds(root, ['arrow_function', 'function_declaration'], []) {
		start := node_start(f)
		if start < doc.lint_start || doc.lint_to_file(start, false) >= 0 {
			continue
		}
		body := node_field(f, 'body') or { continue }
		heads << [start, node_start(body)]!
	}
	return findings.filter(fn [heads] (f Finding) bool {
		if f.rule !in svelte_function_shape_rules {
			return true
		}
		for h in heads {
			if f.stmt.start_byte >= h[0] && f.stmt.start_byte < h[1] {
				return false
			}
		}
		return true
	})
}
