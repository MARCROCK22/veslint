module svelte

// The code veslint's rules parse for a .svelte file (the lint code). ESLint's rules see the
// script and the template expressions in one Program, each template expression under a Svelte
// node of no type they know. The pre-virtual code has them all, but wrapped in statements whose
// shapes some rules check (`if(test){`, `Array.from(list).forEach((item)=>{`, `(expr)as (T);`):
// the lint code is the pre-virtual code with those wrappers made as neutral as JavaScript allows
// while keeping the scopes the template gives (svelte-eslint-parser's scopes come from them):
//
//   expression     `(expr);`                     (the typing dropped)
//   {#if test}     `(test);{` … `}`              (`else ` dropped)
//   {#each}        `(list);((item,i)=>{` … `});` (no context: `()`, `(i)`)
//   let: / then    `(a,b)=>{` … `};`             (the typings dropped)
//   {#snippet}     `function name(a){` … `}`     (the typings and the `return` dropped)
//   then's preparation scripts are dropped.
//
//   bind:x={name} `[(name)+=0];`                 (svelte-eslint-parser makes its reference read-write)
//   {name}         `(name);`                     (an attribute's shorthand: no object)
//
// Every wrapper statement starts with a character of its own, so what a rule reports on a
// wrapper is where the file has nothing (lint_to_file gives -1). The script part is the
// pre-virtual code's: at the file's offsets, markup blank, but without the separator `;` of the
// pre-virtual code (which svelte-eslint-parser drops: a last statement without `;` has none for
// the rules either). The template part follows it, with its own segments (lint_segments) back to
// the file, after an empty block `{}`, which no expression can continue (so the last statement of
// the script ends there, by automatic semicolon insertion, without a token of its own).

// LintEdit replaces [start, end) of the pre-virtual code with `text`.
struct LintEdit {
	start int
	end   int
	text  string
}

// build_lint_code makes Document.lint_code and its segments from the lets.
fn (mut c Conv) build_lint_code() {
	mut doc := c.doc
	pre := doc.pre
	if !c.started || c.lets.len == 0 {
		doc.lint_code = pre
		// Every offset up to the end of the file is the file's.
		doc.lint_start = pre.len + 1
		return
	}
	mut edits := []LintEdit{}
	for l in c.lets {
		segs := l.segments
		match l.kind {
			.expression {
				if segs.len > 0 {
					after := segs.last().pre_start + segs.last().len + 1
					if l.binding && is_js_identifier(pre[segs[0].pre_start..after - 1]) {
						// `(name);` -> `[(name)+=0];`: one reference that reads and writes the
						// name, in an expression whose value is used (not one that only modifies it).
						edits << LintEdit{l.start, l.start + 1, '[('}
						edits << LintEdit{after, l.head_end - 1, '+=0]'}
					} else if l.typed {
						// `(part)as (typing);`: the typing goes.
						edits << LintEdit{after, l.head_end - 1, ''}
					}
				}
			}
			.shorthand_property {
				// `({name});` -> `(name);`
				if segs.len > 0 {
					e := segs[0].pre_start + segs[0].len
					edits << LintEdit{l.start + 1, l.start + 2, ''}
					edits << LintEdit{e, e + 1, ''}
				}
			}
			.if_block {
				// `if(test){` -> `(test);{`
				if segs.len > 0 {
					e := segs[0].pre_start + segs[0].len
					edits << LintEdit{l.start, l.start + 2, ''}
					edits << LintEdit{e, e + 2, ');{'}
				}
			}
			.each_block {
				// `Array.from(list).forEach((item,i)=>{` -> `(list);((item,i)=>{`
				if segs.len > 0 {
					edits << LintEdit{l.start, l.start + 10, ''}
					e := segs[0].pre_start + segs[0].len
					edits << LintEdit{e + 1, e + 9, ';'}
					if !l.has_context {
						// `__$ctx__` (and its comma before an index) goes.
						at := e + 11
						edits << LintEdit{at, at + if l.has_index { 9 } else { 8 }, ''}
					}
				}
			}
			.block_params {
				// `(a: (typing),b: (typing))=>{`: the typings go.
				for k, s in segs {
					from := s.pre_start + s.len
					to := if k + 1 < segs.len { segs[k + 1].pre_start - 1 } else { l.head_end - 4 }
					if to > from {
						edits << LintEdit{from, to, ''}
					}
				}
			}
			.snippet_block {
				for ins in l.insertions {
					edits << LintEdit{ins.pre_start, ins.pre_start + ins.len, ''}
				}
				if l.ts_return {
					close := "return (null as unknown as import('svelte').Snippet)();}"
					edits << LintEdit{l.end - close.len, l.end - 1, ''}
				}
			}
			.prep {
				edits << LintEdit{l.start, l.head_end, ''}
			}
			else {}
		}
	}
	for at in c.else_starts {
		edits << LintEdit{at, at + 5, ''}
	}
	edits.sort(a.start < b.start)
	mut segments := []Segment{}
	for l in c.lets {
		segments << l.segments
	}
	segments.sort(a.pre_start < b.pre_start)
	first := c.lets[0].start
	mut out := []u8{cap: pre.len + 4}
	out << pre[..first].bytes()
	// The separator `;` goes: the empty block ends the script's last statement.
	sep := c.trimmed_len + 1
	if sep < out.len && out[sep] == `;` {
		out[sep] = ` `
	}
	// After a space: the end of the file is not where the template part starts.
	out << ` `
	out << `{`
	out << `}`
	mut lint_segments := []Segment{cap: segments.len}
	for piece in c.lint_pieces(first, segments) {
		emit_lint_piece(pre, piece[0], piece[1], edits, segments, mut out, mut lint_segments)
	}
	doc.lint_code = out.bytestr()
	doc.lint_start = first + 1
	doc.lint_segments = lint_segments
}

// lint_pieces are the ranges of the pre-virtual code's template part in the order of the lint
// code: the render area with each top-level snippet (which the pre-virtual code has after it)
// put back before the first top-level statement that comes after it in the file, then the
// generics; so that the template is in the order of the file, as its nodes are for ESLint.
fn (c &Conv) lint_pieces(first int, segments []Segment) [][2]int {
	render_end := c.trimmed_len + 2 + c.before_spaces.len + c.render.len
	snippet_end := render_end + c.snippet.len
	pre_len := c.doc.pre.len
	// The top-level statements of the render area, with the first position of the file they have.
	mut tops := [][2]int{} // [start, file position]
	mut covered := first
	for l in c.lets {
		if l.start < covered || l.start >= render_end {
			continue
		}
		covered = l.end
		mut fp := -1
		for s in segments {
			if s.pre_start >= l.start && s.pre_start < l.end && (fp < 0 || s.file_start < fp) {
				fp = s.file_start
			}
		}
		tops << [l.start, fp]!
	}
	// The snippets of the snippet area, by where they go.
	mut inserts := map[int][][2]int{}
	covered = render_end
	for l in c.lets {
		if l.start < covered || l.start < render_end || l.start >= snippet_end {
			continue
		}
		covered = l.end
		fp := if l.segments.len > 0 { l.segments[0].file_start } else { -1 }
		mut at := render_end
		for t in tops {
			if fp >= 0 && t[1] > fp {
				at = t[0]
				break
			}
		}
		inserts[at] << [l.start, l.end]!
	}
	mut pieces := [][2]int{}
	mut cursor := first
	mut points := inserts.keys()
	points.sort()
	for at in points {
		if at > cursor {
			pieces << [cursor, at]!
			cursor = at
		}
		pieces << inserts[at]
	}
	if render_end > cursor {
		pieces << [cursor, render_end]!
	}
	// What the snippet area has besides those snippets (nothing, as it is built).
	mut snippet_cursor := render_end
	mut placed := [][2]int{}
	for at in points {
		placed << inserts[at]
	}
	placed.sort(a[0] < b[0])
	for p in placed {
		if p[0] > snippet_cursor {
			pieces << [snippet_cursor, p[0]]!
		}
		snippet_cursor = p[1]
	}
	if snippet_end > snippet_cursor {
		pieces << [snippet_cursor, snippet_end]!
	}
	if pre_len > snippet_end {
		pieces << [snippet_end, pre_len]!
	}
	return pieces
}

// emit_lint_piece copies [from, to) of the pre-virtual code to the lint code with the edits and
// the segments in it.
fn emit_lint_piece(pre string, from int, to int, edits []LintEdit, segments []Segment, mut out []u8, mut lint_segments []Segment) {
	mut cursor := from
	mut si := 0
	for si < segments.len && segments[si].pre_start < from {
		si++
	}
	for e in edits {
		if e.start < cursor || e.start >= to {
			continue
		}
		for si < segments.len && segments[si].pre_start < e.start {
			s := segments[si]
			lint_segments << Segment{s.pre_start - cursor + out.len, s.len, s.file_start}
			si++
		}
		out << pre[cursor..e.start].bytes()
		out << e.text.bytes()
		cursor = e.end
	}
	for si < segments.len && segments[si].pre_start < to {
		s := segments[si]
		lint_segments << Segment{s.pre_start - cursor + out.len, s.len, s.file_start}
		si++
	}
	out << pre[cursor..to].bytes()
}

// lint_text is the source text the rules read for a .svelte file: the file, then the template
// part of the lint code (the lint code differs from it only where the file has markup, which
// the lint code blanks, and at the separator).
pub fn (d &Document) lint_text() string {
	if d.lint_code.len <= d.src.len {
		return d.src
	}
	return d.src + d.lint_code[d.src.len..]
}

// lint_to_file maps a byte offset of the lint code to the file (`end`: the offset ends a
// range): the script part is at the file's offsets, the template expressions through their
// segments; -1 for a wrapper's character.
pub fn (d &Document) lint_to_file(offset int, end bool) int {
	if offset < d.lint_start {
		return if offset <= d.src.len { offset } else { -1 }
	}
	segs := d.lint_segments
	// The last segment that starts at or before the offset (before it, for an end).
	mut lo := 0
	mut hi := segs.len
	for lo < hi {
		mid := (lo + hi) / 2
		if (!end && segs[mid].pre_start <= offset) || (end && segs[mid].pre_start < offset) {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo == 0 {
		return -1
	}
	s := segs[lo - 1]
	if (!end && offset < s.pre_start + s.len) || (end && offset <= s.pre_start + s.len) {
		return s.file_start + offset - s.pre_start
	}
	return -1
}

// lint_end_to_file maps the end of a range of the lint code to the file: where a wrapper's
// character ends it (a template declaration's `;`), the end of the template text before it.
pub fn (d &Document) lint_end_to_file(offset int) int {
	mapped := d.lint_to_file(offset, true)
	if mapped >= 0 || offset < d.lint_start {
		return mapped
	}
	mut best := -1
	for s in d.lint_segments {
		if s.pre_start + s.len <= offset {
			best = s.file_start + s.len
		} else {
			break
		}
	}
	return best
}

// ScriptRange is a <script> element of the document: its range in the file and whether it is
// the module script (`context="module"`, which svelte-eslint-parser's props analysis skips).
pub struct ScriptRange {
pub:
	start          int
	end            int
	context_module bool
}

// script_ranges are the <script> elements of the document.
pub fn (d &Document) script_ranges() []ScriptRange {
	mut out := []ScriptRange{}
	if d.nodes.len == 0 {
		return out
	}
	for child in d.nodes[0].children {
		n := d.nodes[child]
		if n.typ != .script_element {
			continue
		}
		mut module := false
		if n.start_tag >= 0 {
			for a in d.nodes[n.start_tag].attributes {
				an := d.nodes[a]
				if an.typ == .attribute && !an.key.es && an.key.idx >= 0
					&& d.nodes[an.key.idx].name == 'context' && an.values.len == 1
					&& d.nodes[an.values[0]].typ == .literal
					&& d.nodes[an.values[0]].value == 'module' {
					module = true
				}
			}
		}
		out << ScriptRange{
			start:          n.start
			end:            n.end
			context_module: module
		}
	}
	return out
}

// component_snippet_names are the file offsets of the names of the snippets given to a component
// (or to svelte:component or svelte:boundary): analyzeSnippetsScope makes them used, or drops them.
pub fn (d &Document) component_snippet_names() []int {
	mut out := []int{}
	for n in d.nodes {
		if n.typ != .snippet_block || n.parent < 0 || n.id.es == false || n.id.idx < 0 {
			continue
		}
		pn := d.nodes[n.parent]
		if pn.typ != .element {
			continue
		}
		if pn.kind != 'component' {
			if pn.kind != 'special' || pn.name_ref.es || pn.name_ref.idx < 0 {
				continue
			}
			name := d.nodes[pn.name_ref.idx].name
			if name != 'svelte:component' && name != 'svelte:boundary' {
				continue
			}
		}
		out << d.es.nodes[n.id.idx].start
	}
	return out
}

// is_js_identifier: the text is a JavaScript identifier (ASCII letters, digits, `_`, `$` and
// any non-ASCII character, not starting with a digit).
fn is_js_identifier(text string) bool {
	if text.len == 0 || text[0].is_digit() {
		return false
	}
	for b in text {
		if !(b.is_alnum() || b == `_` || b == `$` || b >= 0x80) {
			return false
		}
	}
	return true
}
