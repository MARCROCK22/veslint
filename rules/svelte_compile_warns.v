module rules

import svelte
import svelte_compiler

// Port of eslint-plugin-svelte 3.24.1's shared/svelte-compile-warns (index.ts, ignore-comment.ts,
// extract-leading-comments.ts): the Svelte compiler's warnings for the file, with the
// svelte-ignore comments applied as eslint-plugin-svelte applies them, for svelte/valid-compile
// and svelte/no-unused-svelte-ignore. The compiler is svelte_compiler (a port of Svelte 5.56.0's
// analysis): no JavaScript engine runs.
//
// What eslint-plugin-svelte compiles is the file with the svelte-ignore comments that name codes
// blanked (it applies them itself), the contents of a <style> whose lang is not css stripped
// when it cannot transform them (veslint transforms none: sass, less, stylus and postcss are not
// ported), and every <script> transpiled by TypeScript (the parser services have a program):
// svelte_compiler reads TypeScript as the transpiled JavaScript would read for the warnings
// (svelte_compiler.Options.transpiled), and positions in a script map back to themselves.
// svelte.config.js is not read (no onwarn, warningFilter, compilerOptions.runes).

// SvcIgnoreItem is an IgnoreItem: a code of a svelte-ignore comment (`missing` for a comment
// without one), its range (bytes) and its comment (token).
struct SvcIgnoreItem {
	start              int
	end                int
	code               string
	code_for_v5        string
	read_in_runes_mode bool
	missing            bool
	token              svelte.Token
}

struct SvcWarning {
	code    string
	message string
	start   int = svelte_compiler.no_pos
	end     int = svelte_compiler.no_pos
}

// SvcResult is SvelteCompileWarnings.
struct SvcResult {
	warnings       []SvcWarning
	unused_ignores []SvcIgnoreItem
	is_error       bool
	runes          bool
	// transformed: a script or a style went through a transformation (the locations then come
	// from sourceCode.getLocFromIndex).
	transformed bool
}

const svc_v5_replacements = {
	'non-top-level-reactive-declaration': 'reactive_declaration_invalid_placement'
	'module-script-reactive-declaration': 'reactive_declaration_module_script'
	'empty-block':                        'block_empty'
	'avoid-is':                           'attribute_avoid_is'
	'invalid-html-attribute':             'attribute_invalid_property_name'
	'a11y-structure':                     'a11y_figcaption_parent'
	'illegal-attribute-character':        'attribute_illegal_colon'
	'invalid-rest-eachblock-binding':     'bind_invalid_each_rest'
	'unused-export-let':                  'export_let_unused'
}

const svc_runtime_warning_codes = ['await_reactivity_loss', 'await_waterfall',
	'binding_property_non_reactive', 'hydration_attribute_changed', 'hydration_html_changed',
	'ownership_invalid_binding', 'ownership_invalid_mutation', 'state_snapshot_uncloneable']

const svc_css_warn_codes = ['css-unused-selector', 'css_unused_selector', 'css-invalid-global',
	'css-invalid-global-selector']

// svc_ignore_items is getSvelteIgnoreItems: the codes of every svelte-ignore comment (script
// comments, then HTML comments), sorted by start, descending.
fn (c &Checker) svc_ignore_items() []SvcIgnoreItem {
	doc := c.svelte.doc
	mut items := []SvcIgnoreItem{}
	for comment in doc.comments {
		code_list := snusi_code_list(comment.value) or { continue }
		list_start := comment.value.len - code_list.len
		if snusi_missing_code(code_list) {
			items << SvcIgnoreItem{
				start:   comment.start
				end:     comment.end
				missing: true
				token:   comment
			}
		} else {
			items << svc_extract_ignore(comment.start + 2 + list_start, comment, code_list)
		}
	}
	for token in doc.tokens {
		if token.typ != 'HTMLComment' || token.value.len < 7 {
			continue
		}
		text := token.value[4..token.value.len - 3]
		code_list := snusi_code_list(text) or { continue }
		list_start := text.len - code_list.len
		if snusi_missing_code(code_list) {
			items << SvcIgnoreItem{
				start:   token.start
				end:     token.end
				missing: true
				token:   token
			}
		} else {
			items << svc_extract_ignore(token.start + 4 + list_start, token, code_list)
		}
	}
	items.sort_with_compare(fn (a &SvcIgnoreItem, b &SvcIgnoreItem) int {
		return b.start - a.start
	})
	return items
}

// svc_blank_notes replaces the parenthetical notes (/\([^)]*\)/gu) with spaces.
fn svc_blank_notes(s string) string {
	mut out := s.bytes()
	mut i := 0
	for i < out.len {
		if out[i] == `(` {
			close := s.index_after(')', i + 1) or { -1 }
			if close >= 0 {
				for k in i .. close + 1 {
					out[k] = ` `
				}
				i = close + 1
				continue
			}
		}
		i++
	}
	return out.bytestr()
}

fn svc_is_space(c u8) bool {
	return c in [` `, `\t`, `\n`, `\r`, `\v`, `\f`]
}

fn svc_code_for_v5(code string) string {
	return svc_v5_replacements[code] or { code.replace('-', '_') }
}

// svc_extract_ignore is extractSvelteIgnore: the codes before each separator (/\s*[\s,]\s*/g);
// the whole text only when there is no separator.
fn svc_extract_ignore(start int, token svelte.Token, code_list string) []SvcIgnoreItem {
	runes_starts := svc_runes_mode_code_starts(code_list)
	processed := svc_blank_notes(code_list)
	mut results := []SvcIgnoreItem{}
	mut last_end := 0
	mut i := 0
	for i < processed.len {
		if !svc_is_space(processed[i]) && processed[i] != `,` {
			i++
			continue
		}
		// \s*[\s,]\s*: white space with at most one comma (or a lone comma), and white space.
		sep_start := i
		mut j := i
		for j < processed.len && svc_is_space(processed[j]) {
			j++
		}
		mut sep_end := j
		if j < processed.len && processed[j] == `,` {
			sep_end = j + 1
		}
		for sep_end < processed.len && svc_is_space(processed[sep_end]) {
			sep_end++
		}
		code := processed[last_end..sep_start]
		if code != '' {
			results << SvcIgnoreItem{
				start:              start + last_end
				end:                start + sep_start
				code:               code
				code_for_v5:        svc_code_for_v5(code)
				read_in_runes_mode: last_end in runes_starts
				token:              token
			}
		}
		last_end = sep_end
		i = sep_end
	}
	if results.len == 0 {
		results << SvcIgnoreItem{
			start:              start
			end:                start + processed.len
			code:               processed
			code_for_v5:        svc_code_for_v5(processed)
			read_in_runes_mode: 0 in runes_starts
			token:              token
		}
	}
	return results
}

fn svc_is_code_char(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || (ch >= `0` && ch <= `9`)
		|| ch == `_` || ch == `$` || ch == `-`
}

// svc_runes_mode_code_starts is getRunesModeCodeStarts: the starts of the matches of
// /[\w$-]+(,)?/gu up to the first one without a comma.
fn svc_runes_mode_code_starts(code_list string) []int {
	mut starts := []int{}
	mut i := 0
	for i < code_list.len {
		if !svc_is_code_char(code_list[i]) {
			i++
			continue
		}
		mut e := i
		for e < code_list.len && svc_is_code_char(code_list[e]) {
			e++
		}
		starts << i
		if e >= code_list.len || code_list[e] != `,` {
			break
		}
		i = e + 1
	}
	return starts
}

// ---------------------------------------------------------------------------------------------

// svc_warnings is getSvelteCompileWarnings (cached per file).
fn (mut c Checker) svc_warnings() SvcResult {
	if r := c.svelte.compile {
		return r
	}
	r := c.svc_compute()
	c.svelte.compile = r
	return r
}

fn (mut c Checker) svc_compute() SvcResult {
	doc := c.svelte.doc
	src := doc.src
	// The <style> elements whose lang is not css: their contents are stripped.
	mut strip := []svelte.Token{}
	mut strip_styles := []int{}
	for child in c.svelte_program_body() {
		n := doc.nodes[child]
		if n.typ != .style_element {
			continue
		}
		lang := c.sv_lang_value(child) or { continue }
		if lang.to_lower() == 'css' {
			continue
		}
		strip_styles << child
		for t in n.children {
			tn := doc.nodes[t]
			strip << svelte.Token{
				start: tn.start
				end:   tn.end
			}
		}
	}
	ignore_items := c.svc_ignore_items().filter(!it.missing)
	for item in ignore_items {
		if !strip.any(it.start == item.token.start && it.end == item.token.end) {
			strip << svelte.Token{
				start: item.token.start
				end:   item.token.end
			}
		}
	}
	mut text := src
	if strip.len > 0 {
		// .replace(/[^\t\n\r ]/g, ' '), byte for byte: the offsets stay those of the file (the
		// compiler's lines and UTF-16 columns of the rest are the same either way).
		mut b := src.bytes()
		for t in strip {
			for k in t.start .. t.end {
				if b[k] !in [`\t`, `\n`, `\r`, ` `] {
					b[k] = ` `
				}
			}
		}
		text = b.bytestr()
	}
	mut has_script := false
	for child in c.svelte_program_body() {
		if doc.nodes[child].typ == .script_element {
			has_script = true
		}
	}
	config := c.svelte_config(c.sv_file_path(c.svelte.ts_path))
	compiled := svc_compile(text, doc, c.svelte.parsers, svelte_compiler.Options{
		custom_element: c.svc_custom_element()
		transpiled:     true
		runes:          config.runes
		async:          config.async
	}, c.script_target <= 1)
	if compiled.is_error {
		return SvcResult{
			warnings:       compiled.warnings
			unused_ignores: ignore_items
			is_error:       true
			transformed:    has_script
		}
	}
	mut warnings := []SvcWarning{}
	mut unused := ignore_items.clone()
	for w in compiled.warnings {
		// Without svelte-ignore comments nothing is ignored.
		if ignore_items.len == 0 || !c.svc_ignored(w, ignore_items, mut unused) {
			warnings << w
		}
	}
	// Stripped styles cannot give CSS warnings: a CSS code before one counts as used.
	for style in strip_styles {
		mut comments := c.svc_leading_comments(svelte.Ref{
			es:  false
			idx: style
		})
		comments.reverse()
		for comment in comments {
			mut hit := false
			for item in ignore_items {
				if item.token.start == comment.start && (item.code in svc_css_warn_codes
					|| item.code_for_v5 in svc_css_warn_codes) {
					hit = true
					for k, u in unused {
						if u.start == item.start && u.end == item.end {
							unused.delete(k)
							break
						}
					}
					break
				}
			}
			if hit {
				break
			}
		}
	}
	// compilerOptions.runes applies unless <svelte:options runes> is there, as in Svelte.
	runes := if c.svc_options_runes() || config.runes < 0 {
		compiled.runes
	} else {
		config.runes == 1
	}
	return SvcResult{
		warnings:       warnings
		unused_ignores: unused
		runes:          runes
		transformed:    has_script
	}
}

struct SvcCompiled {
	warnings []SvcWarning
	is_error bool
	runes    bool
}

// svc_compile runs the port of compile() on `text` (the file, or the file with parts blanked).
fn svc_compile(text string, doc &svelte.Document, parsers &svelte.Parsers, opts svelte_compiler.Options, es5 bool) SvcCompiled {
	mut d := unsafe { doc }
	mut own := false
	if text != doc.src {
		d = if parsers != unsafe { nil } {
			svelte.parse_svelte_with(text, parsers) or { return SvcCompiled{} }
		} else {
			svelte.parse_svelte(text) or { return SvcCompiled{} }
		}
		own = true
	}
	defer {
		if own {
			d.free()
		}
	}
	if _ := d.error {
		// The blanked text no longer parses (it should not happen): no warnings.
		return SvcCompiled{}
	}
	component := svelte_compiler.build_component_with(d, true, es5) or {
		if err is svelte_compiler.CompileError {
			return SvcCompiled{
				warnings: [
					SvcWarning{
						code:    err.diag.code
						message: err.diag.message
						start:   err.start
						end:     err.end
					},
				]
				is_error: true
			}
		}
		return SvcCompiled{}
	}
	result := svelte_compiler.analyze(component, opts)
	if e := result.error {
		return SvcCompiled{
			warnings: [
				SvcWarning{
					code:    e.diag.code
					message: e.diag.message
					start:   e.start
					end:     e.end
				},
			]
			is_error: true
		}
	}
	mut warnings := []SvcWarning{}
	for w in result.warnings {
		warnings << SvcWarning{
			code:    w.code
			message: w.message
			start:   w.start
			end:     w.end
		}
	}
	return SvcCompiled{
		warnings: warnings
		runes:    result.runes
	}
}

// svc_custom_element is isCustomElement: <svelte:options> with `tag` or `customElement`.
fn (c &Checker) svc_custom_element() bool {
	doc := c.svelte.doc
	for child in c.svelte_program_body() {
		n := doc.nodes[child]
		if n.typ != .element || n.kind != 'special' || c.sv_element_name(child) != 'svelte:options' {
			continue
		}
		if c.sv_find_attribute(child, 'tag') >= 0 || c.sv_find_attribute(child, 'customElement') >= 0 {
			return true
		}
	}
	return false
}

// svc_options_runes is hasSvelteOptionsRunes: <svelte:options> with a `runes` attribute.
fn (c &Checker) svc_options_runes() bool {
	doc := c.svelte.doc
	for child in c.svelte_program_body() {
		n := doc.nodes[child]
		if n.typ == .element && n.kind == 'special' && c.sv_element_name(child) == 'svelte:options'
			&& c.sv_find_attribute(child, 'runes') >= 0 {
			return true
		}
	}
	return false
}

fn (c &Checker) svelte_program_body() []int {
	return c.svelte.doc.nodes[0].children
}

// ---------------------------------------------------------------------------------------------
// processIgnore.

// svc_ignored applies the svelte-ignore comments to a warning: true when one ignores it (the
// comments that do leave `unused`).
fn (mut c Checker) svc_ignored(w SvcWarning, items []SvcIgnoreItem, mut unused []SvcIgnoreItem) bool {
	if w.code == '' {
		return false
	}
	mut ignored := false
	if w.start != svelte_compiler.no_pos {
		// iterateNestedScriptNodes
		mut node := c.svc_node_at(w.start)
		for {
			r := node or { break }
			if !c.svc_is_js(r) {
				break
			}
			p := c.sv_parent(r) or { break }
			if c.svc_type(p) == 'Program' {
				break
			}
			if c.svc_check_comments(w, r, items, mut unused) {
				ignored = true
			}
			node = p
		}
	}
	mut target := c.svc_warning_node(w)
	for {
		r := target or { break }
		if c.svc_check_comments(w, r, items, mut unused) {
			ignored = true
		}
		target = c.svc_ignore_parent(r)
	}
	return ignored
}

fn (c &Checker) svc_type(r svelte.Ref) string {
	doc := c.svelte.doc
	return if r.es { doc.es_type_name(r.idx) } else { doc.nodes[r.idx].typ.type_name() }
}

fn (c &Checker) svc_range(r svelte.Ref) (int, int) {
	doc := c.svelte.doc
	if r.es {
		return doc.es.nodes[r.idx].start, doc.es.nodes[r.idx].end
	}
	return doc.nodes[r.idx].start, doc.nodes[r.idx].end
}

fn (c &Checker) svc_is_js(r svelte.Ref) bool {
	typ := c.svc_type(r)
	return typ != 'Program' && !typ.starts_with('Svelte')
}

// SvcNodeIndex is the traversal's nodes in entering order with their ranges and children (in
// order), and whether each node's children are sorted by start without overlapping (then
// svc_node_at finds the child that holds an offset by a binary search).
struct SvcNodeIndex {
mut:
	refs     []svelte.Ref
	start    []int
	end      []int
	children [][]int
	sorted   []bool
}

fn (mut c Checker) svc_node_index() &SvcNodeIndex {
	if idx := c.svelte.node_index {
		return idx
	}
	mut idx := &SvcNodeIndex{}
	mut stack := []int{}
	for step in c.sv_steps() {
		if step.leave {
			stack.pop()
			continue
		}
		start, end := c.svc_range(step.node)
		k := idx.refs.len
		if stack.len > 0 {
			idx.children[stack.last()] << k
		}
		stack << k
		idx.refs << step.node
		idx.start << start
		idx.end << end
		idx.children << []int{}
		idx.sorted << true
	}
	for k, kids in idx.children {
		for m in 1 .. kids.len {
			if idx.start[kids[m]] < idx.end[kids[m - 1]] {
				idx.sorted[k] = false
				break
			}
		}
	}
	c.svelte.node_index = idx
	return idx
}

// svc_node_at is sourceCode.getNodeByRangeIndex: the deepest node whose range holds `index`
// (ESLint's traversal enters the first child that holds it, skipping the others).
fn (mut c Checker) svc_node_at(index int) ?svelte.Ref {
	idx := c.svc_node_index()
	if idx.refs.len == 0 || !(idx.start[0] <= index && index < idx.end[0]) {
		return none
	}
	mut cur := 0
	for {
		kids := idx.children[cur]
		mut next := -1
		if idx.sorted[cur] {
			// The last child that starts at or before `index`.
			mut lo := 0
			mut hi := kids.len
			for lo < hi {
				mid := (lo + hi) / 2
				if idx.start[kids[mid]] <= index {
					lo = mid + 1
				} else {
					hi = mid
				}
			}
			if lo > 0 && index < idx.end[kids[lo - 1]] {
				next = kids[lo - 1]
			}
		} else {
			for k in kids {
				if idx.start[k] <= index && index < idx.end[k] {
					next = k
					break
				}
			}
		}
		if next < 0 {
			break
		}
		cur = next
	}
	return idx.refs[cur]
}

fn (mut c Checker) svc_warning_node(w SvcWarning) ?svelte.Ref {
	if w.start != svelte_compiler.no_pos {
		if n := c.svc_target_at(w.start) {
			return n
		}
		if w.end != svelte_compiler.no_pos {
			return c.svc_target_at(w.start + (w.end - w.start) / 2)
		}
	}
	if w.end != svelte_compiler.no_pos {
		return c.svc_target_at(w.end)
	}
	return none
}

// svc_target_at is getWarningTargetNodeFromIndex.
fn (mut c Checker) svc_target_at(index int) ?svelte.Ref {
	mut node := c.svc_node_at(index)
	for {
		r := node or { return none }
		typ := c.svc_type(r)
		if typ == 'SvelteElement' || typ == 'SvelteStyleElement' {
			return r
		}
		p := c.sv_parent(r) or { return none }
		pt := c.svc_type(p)
		if pt == 'Program' || pt == 'SvelteScriptElement' {
			return r
		}
		node = p
	}
	return none
}

// svc_ignore_parent is getIgnoreParent.
fn (c &Checker) svc_ignore_parent(r svelte.Ref) ?svelte.Ref {
	typ := c.svc_type(r)
	if typ !in ['SvelteElement', 'SvelteIfBlock', 'SvelteKeyBlock', 'SvelteEachBlock',
		'SvelteAwaitBlock'] {
		return none
	}
	parent := c.sv_parent(r) or { return none }
	pt := c.svc_type(parent)
	if pt == 'SvelteElseBlock' {
		return c.sv_parent(parent)
	}
	if pt in ['SvelteAwaitPendingBlock', 'SvelteAwaitThenBlock', 'SvelteAwaitCatchBlock'] {
		return c.sv_parent(parent)
	}
	if pt !in ['SvelteElement', 'SvelteIfBlock', 'SvelteKeyBlock', 'SvelteEachBlock'] {
		return none
	}
	return parent
}

// svc_check_comments: a leading comment of the node (the last first) that ignores the warning's
// code; the first such comment is used.
fn (mut c Checker) svc_check_comments(w SvcWarning, node svelte.Ref, items []SvcIgnoreItem, mut unused []SvcIgnoreItem) bool {
	mut comments := c.svc_leading_comments(node)
	comments.reverse()
	for comment in comments {
		if c.svc_is_trailing_comment(comment) {
			continue
		}
		for item in items {
			if item.token.start == comment.start && item.token.end == comment.end
				&& (item.code == w.code || item.code_for_v5 == w.code) {
				for k, u in unused {
					if u.start == item.start && u.end == item.end {
						unused.delete(k)
						break
					}
				}
				return true
			}
		}
	}
	return false
}

// svc_leading_comments is extractLeadingComments: the comments between the token before the node
// (no `(`, HTML text or HTML comment) and the node.
fn (c &Checker) svc_leading_comments(node svelte.Ref) []svelte.Token {
	start, _ := c.svc_range(node)
	mut before := start
	mut from := 0
	for {
		t := c.sv_token_before(before, false) or { break }
		if sv_is_punctuator(t, '(') || t.typ == 'HTMLText' || t.typ == 'HTMLComment' {
			before = t.start
			continue
		}
		from = t.end
		break
	}
	return c.sv_tokens_between(from, start, true).filter(it.typ in ['HTMLComment', 'Block', 'Line'])
}

// svc_is_trailing_comment is isTrailingComment: a script comment the compiler attaches to the
// node before it (`a, // comment`).
fn (mut c Checker) svc_is_trailing_comment(comment svelte.Token) bool {
	if comment.typ != 'Line' && comment.typ != 'Block' {
		return false
	}
	src := c.svelte.doc.src
	mut index := comment.start
	for index > 0 && src[index - 1] in [`\t`, ` `, `)`, `,`] {
		index--
	}
	for index > 0 && index <= comment.start {
		mut node := c.svc_node_at(index - 1)
		for {
			r := node or { break }
			if !c.svc_is_js(r) {
				break
			}
			_, end := c.svc_range(r)
			if end == index {
				return true
			}
			node = c.sv_parent(r)
		}
		index++
	}
	return false
}
