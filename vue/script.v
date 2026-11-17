module vue

import estree
import jsregexp
import treesitter

// The <script> side of a .vue file: which scripts make the Program, their language, the code
// vue-eslint-parser hands typescript-eslint for them (src/script/index.ts parseScriptElement and
// src/script-setup/index.ts: a <script> with a <script setup> becomes one module, the imports of
// the setup hoisted, its other statements in a block, its `export default` last) with the map of
// that code to the file, and the Program's range. The script itself is parsed by tree-sitter on
// masked_script: the file with everything but the script contents blanked, so positions are file
// positions.

pub enum ScriptLang {
	none // no <script>: the template is linted alone
	js   // a script without lang="ts"/"tsx" (an empty <script></script> too): skipped by veslint
	ts
	tsx
}

// RemapBlock maps a piece of the synthetic code to the file: [gen_start, gen_end) of the code
// is at gen + delta of the file (bytes).
pub struct RemapBlock {
pub:
	gen_start int
	gen_end   int
	delta     int
}

// ScriptInfo is what the parser knows of the scripts.
pub struct ScriptInfo {
pub mut:
	// scripts are the top-level <script> elements; parsed the ones whose contents are the
	// Program (the first script, or a <script> and a <script setup>).
	scripts []int
	parsed  []int
	lang    ScriptLang
	// The Program's range, tokens and comments as vue-eslint-parser gives them (the tokens with
	// the `<script>`/`</script>` punctuators of the tags).
	program_start int
	program_end   int
	tokens        []Token
	comments      []Token
	// codes are the codes handed to the script parser for the scripts: the setup alone (the
	// pre-pass of a <script setup> with a <script>) and `code`.
	codes []string
	// code is the code typescript-eslint parses (and type-checks) for the scripts. With one
	// script it is its content (after `type T = …;` for a generic): file = code offset + `offset`.
	// With two it is the synthetic module: see remap, synthetic_to_file.
	code     string
	combined bool
	offset   int
	remap    []RemapBlock
	// split_punctuators are the offsets in `code` of the `;`, `{`, `}`, `(`, `)` it adds.
	split_punctuators []int
	// The range of the block of the setup statements in `code`.
	setup_block_start int
	setup_block_end   int
	// masked is masked_script: same length as the file. split_offsets are where it puts a `;`
	// between two scripts (they would be one statement otherwise), whose EmptyStatement is not
	// in `es`'s Program body.
	masked        string
	split_offsets []int
	tree          &C.TSTree = unsafe { nil }
	es            estree.EsTree
	has_es        bool
	// has_error: tree-sitter found syntax errors in the script (vue-eslint-parser throws a
	// parsing error from TypeScript then); error_index is where.
	has_error   bool
	error_index int
}

// script_lang is getParserLangFromSFC: the lang of the <script setup> when there are exactly two
// scripts and one is setup, else of the first script; none without a script or a lang.
pub fn (d &Document) script_lang() ?string {
	scripts := d.top_elements('script')
	mut script := -1
	if scripts.len == 2 {
		for s in scripts {
			if d.is_script_setup(s) {
				script = s
				break
			}
		}
	}
	if script < 0 && scripts.len > 0 {
		script = scripts[0]
	}
	if script < 0 {
		return none
	}
	return d.lang_of(script)
}

// masked_script is the file with every character but those of the parsed script contents (and
// the split `;`) replaced by a space, line breaks kept: tree-sitter positions in it are file
// positions.
pub fn (d &Document) masked_script() string {
	return d.script.masked
}

// synthetic_to_file maps an offset of ScriptInfo.code to the file as vue-eslint-parser's
// remapping does (`end`: the offset ends a range). Out of every block (on an added punctuator)
// the original gives back the offset itself as the shift, so the result is twice the offset:
// that is kept, as it is what vue-eslint-parser reports there.
pub fn (s &ScriptInfo) synthetic_to_file(offset int, end bool) int {
	if !s.combined {
		return offset + s.offset
	}
	for b in s.remap {
		if (!end && b.gen_start <= offset && offset < b.gen_end)
			|| (end && b.gen_start < offset && offset <= b.gen_end) {
			return offset + b.delta
		}
	}
	return offset + offset
}

// text_child is the VText child of a script, if its first child is one.
fn (d &Document) text_child(element int) int {
	children := d.nodes[element].children
	if children.len > 0 && d.nodes[children[0]].typ == .v_text {
		return children[0]
	}
	return -1
}

// CodeBlocks builds the synthetic code (CodeBlocks of script-setup/index.ts), offsets in bytes.
struct CodeBlocks {
mut:
	code  string
	remap []RemapBlock
	split []int
}

fn (mut cb CodeBlocks) append(text string, file_offset int) {
	start := cb.code.len
	cb.code += js_trim_end(text)
	cb.remap << RemapBlock{start, cb.code.len, file_offset - start}
}

fn (mut cb CodeBlocks) append_split(p string) {
	cb.split << cb.code.len
	cb.split << cb.code.len + 1
	cb.code += '\n${p}\n'
}

fn (mut cb CodeBlocks) append_blocks(other CodeBlocks) {
	start := cb.code.len
	cb.code += other.code
	for b in other.remap {
		cb.remap << RemapBlock{b.gen_start + start, b.gen_end + start, b.delta - start}
	}
	for s in other.split {
		cb.split << s + start
	}
}

// GenericDefine is a `type T = constraint` of a generic <script setup> (extractGeneric).
struct GenericDefine {
	define string
	start  int // the parameter's start in the file
}

fn (c &ExprContext) extract_generic(element int) []GenericDefine {
	start_tag := c.doc.nodes[c.doc.nodes[element].start_tag]
	for a in start_tag.attributes {
		attr := c.doc.nodes[a]
		if !attr.directive || attr.value < 0 {
			continue
		}
		expr := c.doc.nodes[attr.value].expression
		if expr.kind != .vnode || c.doc.nodes[expr.node].typ != .v_generic_expression {
			continue
		}
		g := c.doc.nodes[expr.node]
		mut out := []GenericDefine{}
		for i, p in g.exprs {
			es := c.es(p.snippet)
			name_node := es.node(p.node, .name) or { -1 }
			name := if name_node >= 0 { es.string_of(name_node, .name) or { '' } } else { '' }
			has_constraint := (es.node(p.node, .constraint) or { -1 }) >= 0
			constraint := if has_constraint {
				generic_constraint(name, g.raw_params[i])
			} else {
				'unknown'
			}
			out << GenericDefine{
				define: 'type ${name} = ${constraint}'
				start:  es.nodes[p.node].start
			}
		}
		return out
	}
	return []GenericDefine{}
}

// generic_constraint is getConstraint: the text after `extends` up to a `=` (a default, which is
// dropped) that is not `=>`, skipping comments.
fn generic_constraint(name string, raw string) string {
	mut index := (raw.index(name) or { -1 }) + name.len
	mut start := -1
	for index < raw.len {
		if start < 0 {
			if raw[index..].starts_with('extends') {
				index += 7
				start = index
				continue
			}
		} else if raw[index] == `=` {
			if index + 1 < raw.len && raw[index + 1] == `>` {
				index += 2
				continue
			}
			return raw[start..index]
		}
		if raw[index..].starts_with('//') {
			lf := raw.index_after_('\n', index)
			if lf >= 0 {
				index = lf + 1
				continue
			}
			return 'unknown'
		}
		if raw[index..].starts_with('/*') {
			close := raw.index_after_('*/', index)
			if close >= 0 {
				index = close + 2
				continue
			}
			return 'unknown'
		}
		index++
	}
	if start < 0 {
		return 'unknown'
	}
	return raw[start..]
}

fn (mut c ExprContext) parse_script() {
	mut s := &c.doc.script
	s.scripts = c.doc.top_elements('script')
	lang := c.doc.script_lang() or { '' }
	s.lang = if s.scripts.len == 0 {
		ScriptLang.none
	} else if lang == 'ts' {
		ScriptLang.ts
	} else if lang == 'tsx' {
		ScriptLang.tsx
	} else {
		ScriptLang.js
	}
	if s.scripts.len == 0 {
		s.codes << ''
		s.masked = blank(c.doc.src, [])
		return
	}
	mut setup := -1
	if s.scripts.len == 2 {
		for e in s.scripts {
			if c.doc.is_script_setup(e) {
				setup = e
				break
			}
		}
	}
	if setup >= 0 {
		other := if s.scripts[0] == setup { s.scripts[1] } else { s.scripts[0] }
		s.parsed = [other, setup]
		c.parse_combined(setup, other)
	} else {
		s.parsed = [s.scripts[0]]
		c.parse_single(s.scripts[0])
	}
}

// blank replaces every character of `src` out of the ranges by spaces, line breaks kept.
fn blank(src string, ranges [][]int) string {
	mut out := []u8{len: src.len, init: ` `}
	for i, ch in src {
		if ch == `\n` || ch == `\r` {
			out[i] = ch
		}
	}
	for r in ranges {
		for i in r[0] .. r[1] {
			out[i] = src[i]
		}
	}
	return out.bytestr()
}

// parse_masked parses the masked script and keeps its tree and ESTree.
fn (mut c ExprContext) parse_masked(ranges [][]int) {
	mut s := &c.doc.script
	mut masked := blank(c.doc.src, ranges).bytes()
	for o in s.split_offsets {
		masked[o] = `;`
	}
	s.masked = masked.bytestr()
	tsx := s.lang == .tsx
	tree := parse_ts(if tsx { c.tsx } else { c.ts }, s.masked) or { return }
	s.tree = tree
	root := treesitter.root_node(tree)
	if C.ts_node_has_error(root) {
		s.has_error = true
		s.error_index = first_error_offset(root)
	}
	es := estree.convert_with(root, s.masked, tsx, estree.Options{
		module:       true
		allow_errors: true
		regexp_valid: fn (pattern string, flags string) bool {
			return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
		}
	}) or { return }
	s.es = es
	s.has_es = true
	toks, comms := snippet_tokens(root, s.masked)
	for t in toks {
		if t.start in s.split_offsets {
			continue
		}
		value := s.masked[t.start..t.end]
		s.tokens << Token{
			typ:   t.typ
			start: t.start
			end:   t.end
			value: if t.typ == 'PrivateIdentifier' { value[1..] } else { value }
		}
	}
	for t in comms {
		// A `//` comment at the end of a content would run on into the blanked end tag.
		mut end := t.end
		for r in ranges {
			if t.start >= r[0] && t.start < r[1] && end > r[1] {
				end = r[1]
			}
		}
		s.comments << Token{
			typ:   t.typ
			start: t.start
			end:   end
			value: if t.typ == 'Block' {
				s.masked[t.start + 2..end - 2]
			} else {
				s.masked[t.start + 2..end]
			}
		}
	}
	if s.split_offsets.len > 0 {
		c.drop_split_statements()
	}
}

// drop_split_statements takes the EmptyStatements of the split `;` out of the Program body and
// ends the nodes that ended with one at the token before it (remapLocationAndTokens's endMap).
fn (mut c ExprContext) drop_split_statements() {
	mut s := &c.doc.script
	mut end_map := map[int]int{}
	for o in s.split_offsets {
		index := sorted_index_by_start(s.tokens, o)
		end_map[o + 1] = if index > 0 { s.tokens[index - 1].end } else { o }
	}
	for mut n in s.es.nodes {
		if new_end := end_map[n.end] {
			n.end = new_end
		}
	}
	root := s.es.root
	if p := s.es.prop(root, .body) {
		if p.kind == .list {
			s.es.lists[p.idx] = s.es.lists[p.idx].filter(!(s.es.typ(it) == .empty_statement
				&& s.es.nodes[it].start in s.split_offsets))
		}
	}
}

// script_tag_tokens adds the `<script>` and `</script>` punctuators of the elements and sorts
// the tokens.
fn (mut c ExprContext) script_tag_tokens(elements []int) {
	mut s := &c.doc.script
	for e in elements {
		el := c.doc.nodes[e]
		st := c.doc.nodes[el.start_tag]
		s.tokens << Token{
			typ:   'Punctuator'
			start: st.start
			end:   st.end
			value: '<script>'
		}
		if el.end_tag >= 0 {
			et := c.doc.nodes[el.end_tag]
			s.tokens << Token{
				typ:   'Punctuator'
				start: et.start
				end:   et.end
				value: '</script>'
			}
		}
	}
	s.tokens.sort_with_compare(fn (a &Token, b &Token) int {
		return a.start - b.start
	})
}

// parse_single is parseScriptElement.
fn (mut c ExprContext) parse_single(element int) {
	mut s := &c.doc.script
	text := c.doc.text_child(element)
	if text < 0 {
		start_tag_end := c.doc.nodes[c.doc.nodes[element].start_tag].end
		s.code = ''
		s.offset = start_tag_end
		s.codes << ''
		s.program_start = start_tag_end
		s.program_end = start_tag_end
		s.masked = blank(c.doc.src, [])
		c.script_tag_tokens([element])
		return
	}
	t := c.doc.nodes[text]
	content := c.doc.src[t.start..t.end]
	defines := c.extract_generic(element)
	mut defs := ''
	if defines.len > 0 {
		defs = defines.map(it.define).join(';') + ';\n'
	}
	s.code = defs + content
	s.offset = t.start - defs.len
	s.codes << s.code
	c.parse_masked([[t.start, t.end]])
	s.program_start = t.start
	s.program_end = t.end
	if defines.len > 0 {
		// The Program starts at the start of the code (in the start tag), unless its first
		// statement, token or comment gives it back its place.
		u := c.doc.utf16(t.start) - utf16_length(defs)
		s.program_start = c.to_bytes(u)
		mut first := -1
		if s.has_es {
			body := s.es.list(s.es.root, .body) or { []int{} }
			if body.len > 0 {
				first = s.es.nodes[body[0]].start
			}
		}
		if s.tokens.len > 0 && (first < 0 || s.tokens[0].start < first) {
			first = s.tokens[0].start
		}
		if s.comments.len > 0 && (first < 0 || s.comments[0].start < first) {
			first = s.comments[0].start
		}
		if first >= 0 {
			s.program_start = first
		}
	}
	c.script_tag_tokens([element])
}

// parse_combined is parseScriptSetupElements.
fn (mut c ExprContext) parse_combined(setup int, other int) {
	mut s := &c.doc.script
	setup_text := c.doc.text_child(setup)
	other_text := c.doc.text_child(other)
	mut ranges := [][]int{}
	for t in [other_text, setup_text] {
		if t >= 0 {
			ranges << [c.doc.nodes[t].start, c.doc.nodes[t].end]
		}
	}
	ranges.sort(a[0] < b[0])
	if ranges.len == 2 {
		// A `;` right before the second content keeps the two from making one statement.
		s.split_offsets << ranges[1][0] - 1
	}
	if setup_text < 0 {
		if other_text < 0 {
			// No code blocks: an empty script without the tag tokens.
			start_tag_end := c.doc.nodes[c.doc.nodes[setup].start_tag].end
			s.code = ''
			s.offset = start_tag_end
			s.codes << ''
			s.program_start = start_tag_end
			s.program_end = start_tag_end
			s.masked = blank(c.doc.src, [])
			return
		}
	}
	c.parse_masked(ranges)
	mut final := CodeBlocks{}
	if setup_text >= 0 {
		// The pre-pass parses the setup content alone.
		st := c.doc.nodes[setup_text]
		s.codes << c.doc.src[st.start..st.end]
		sb := c.setup_code_blocks(setup, setup_text) or {
			s.has_error = true
			return
		}
		if other_text >= 0 {
			ot := c.doc.nodes[other_text]
			final.append(c.doc.src[ot.start..ot.end], ot.start)
			final.append_split(';')
			setup_offset := final.code.len
			final.append_blocks(sb.blocks)
			s.setup_block_start = sb.block_start + setup_offset
			s.setup_block_end = sb.block_end + setup_offset
		} else {
			final = sb.blocks
			s.setup_block_start = sb.block_start
			s.setup_block_end = sb.block_end
		}
	} else {
		ot := c.doc.nodes[other_text]
		final.append(c.doc.src[ot.start..ot.end], ot.start)
	}
	s.combined = true
	s.code = final.code
	s.remap = final.remap
	s.split_punctuators = final.split
	s.codes << s.code
	// The Program starts at the remapped start of the code, or at an earlier statement, and
	// ends with its last statement.
	start0 := s.synthetic_to_file(0, false)
	mut start := start0
	mut end := 0
	if s.has_es {
		for st in s.es.list(s.es.root, .body) or { []int{} } {
			n := s.es.nodes[st]
			if n.start < start {
				start = n.start
			}
			if n.end > end {
				end = n.end
			}
		}
	}
	s.program_start = start
	s.program_end = end
	c.script_tag_tokens([setup, other])
}

struct SetupBlocks {
	blocks      CodeBlocks
	block_start int
	block_end   int
}

// setup_code_blocks is getScriptSetupCodeBlocks, on the statements of the setup content in the
// masked script's tree.
fn (mut c ExprContext) setup_code_blocks(setup int, text int) !SetupBlocks {
	s := &c.doc.script
	if !s.has_es {
		return error('no tree')
	}
	es := &s.es
	t := c.doc.nodes[text]
	base := t.start
	code := c.doc.src[t.start..t.end]
	mut imports := CodeBlocks{}
	mut statements := CodeBlocks{}
	mut export_defaults := CodeBlocks{}
	mut used := 0
	// The statements of the setup content, relative to it.
	mut body := []int{}
	for st in es.list(es.root, .body) or { []int{} } {
		if es.nodes[st].start >= t.start && es.nodes[st].end <= t.end {
			body << st
		}
	}
	for st in body {
		typ := es.typ(st)
		full_start, full_end := full_range(es, st)
		start := full_start - base
		end := full_end - base
		if typ == .import_declaration || typ == .export_all_declaration
			|| (typ == .export_named_declaration && (es.node(st, .source) or { -1 }) >= 0) {
			used = append_statement(mut statements, code, base, used, start, used)
			used = append_statement(mut imports, code, base, start, end, used)
		} else if typ == .export_default_declaration {
			used = append_statement(mut statements, code, base, used, start, used)
			used = append_statement(mut export_defaults, code, base, start, end, used)
		} else if typ == .export_named_declaration {
			used = append_statement(mut statements, code, base, used, start, used)
			export_index := sorted_index_by_start(s.tokens, es.nodes[st].start)
			if export_index < s.tokens.len && s.tokens[export_index].start == es.nodes[st].start
				&& s.tokens[export_index].value == 'export' {
				export_token := s.tokens[export_index]
				used = append_code(mut statements, code, base, used, export_token.start - base,
					used)
				if (es.node(st, .declaration) or { -1 }) >= 0 {
					used = append_statement(mut statements, code, base, export_token.end - base,
						end, used)
				} else {
					statements.append_split('(')
					mut cursor := export_token.end - base
					for spec in es.list(st, .specifiers) or { []int{} } {
						local := es.node(spec, .local) or { continue }
						exported := es.node(spec, .exported) or { continue }
						if es.nodes[local].start < es.nodes[exported].start {
							li := sorted_index_by_start(s.tokens, es.nodes[local].start)
							if li + 2 >= s.tokens.len || s.tokens[li + 1].value != 'as' {
								return error('Could not parse <script setup>.')
							}
							as_token := s.tokens[li + 1]
							exported_token := s.tokens[li + 2]
							used = append_code(mut statements, code, base, cursor, as_token.start - base,
								used)
							used = append_code(mut statements, code, base, as_token.end - base,
								exported_token.start - base, used)
							cursor = exported_token.end - base
						}
					}
					used = append_code(mut statements, code, base, cursor, end, used)
					statements.append_split(')')
					statements.append_split(';')
				}
			} else {
				used = append_statement(mut statements, code, base, used, end, used)
			}
		}
	}
	used = append_statement(mut statements, code, base, used, code.len, used)
	mut blocks := CodeBlocks{}
	blocks.append_blocks(imports)
	block_start := blocks.code.len
	blocks.append_split('{')
	for d in c.extract_generic(setup) {
		blocks.append(d.define, d.start)
		blocks.append_split(';')
	}
	blocks.append_blocks(statements)
	blocks.append_split('}')
	block_end := blocks.code.len
	blocks.append_blocks(export_defaults)
	return SetupBlocks{
		blocks:      blocks
		block_start: block_start
		block_end:   block_end
	}
}

// append_code is `append` of getScriptSetupCodeBlocks: appends the code from start to end, if
// any; gives the new used offset (`end`, or `used` when nothing was appended).
fn append_code(mut cb CodeBlocks, code string, base int, start int, end int, used int) int {
	if start < end {
		cb.append(code[start..end], base + start)
		return end
	}
	return used
}

// append_statement is appendRangeAsStatement: append_code and, if it appended, a split `;`.
fn append_statement(mut cb CodeBlocks, code string, base int, start int, end int, used int) int {
	if start < end {
		cb.append(code[start..end], base + start)
		cb.append_split(';')
		return end
	}
	return used
}

// full_range is getNodeFullRange: the range over the node and all its descendants.
fn full_range(es &estree.EsTree, n int) (int, int) {
	mut start := es.nodes[n].start
	mut end := es.nodes[n].end
	mut stack := [n]
	for stack.len > 0 {
		i := stack.pop()
		if es.nodes[i].start < start {
			start = es.nodes[i].start
		}
		if es.nodes[i].end > end {
			end = es.nodes[i].end
		}
		stack << es.children(i)
	}
	return start, end
}
