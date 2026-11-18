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
// Every wrapper statement starts with a character of its own, so what a rule reports on a
// wrapper is where the file has nothing (lint_to_file gives -1). The script part is the
// pre-virtual code's: at the file's offsets, markup blank, the separator `\n;` where the script
// ends. The template part follows it, with its own segments (lint_segments) back to the file.

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
		doc.lint_start = pre.len
		return
	}
	mut edits := []LintEdit{}
	for l in c.lets {
		segs := l.segments
		match l.kind {
			.expression {
				if l.typed && segs.len > 0 {
					// `(part)as (typing);`: the typing goes.
					edits << LintEdit{segs.last().pre_start + segs.last().len + 1, l.head_end - 1, ''}
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
	mut out := []u8{cap: pre.len}
	out << pre[..first].bytes()
	mut cursor := first
	mut si := 0
	mut lint_segments := []Segment{cap: segments.len}
	for e in edits {
		if e.start < cursor {
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
	for si < segments.len {
		s := segments[si]
		lint_segments << Segment{s.pre_start - cursor + out.len, s.len, s.file_start}
		si++
	}
	out << pre[cursor..].bytes()
	doc.lint_code = out.bytestr()
	doc.lint_start = first
	doc.lint_segments = lint_segments
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
// segments; -1 for a wrapper's character (or the separator).
pub fn (d &Document) lint_to_file(offset int, end bool) int {
	if offset < d.lint_start {
		if d.separator >= 0 && (offset == d.separator + 1 || (!end && offset == d.separator)) {
			return -1
		}
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
