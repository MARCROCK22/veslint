module tsgo

// Navigation of the binary AST of any file of the program (lib.*.d.ts and packages included), like
// the RemoteNode of TypeScript 7.1.0-beta (dist/api/node/node.generated.js and node.js): each row of the
// node table has the index of its next sibling and of its parent; the children of a node start at
// the next row (when that row's parent is the node) and follow `next` until 0. A NodeList row (kind
// 0xFFFFFFFF, whose data is its length) holds the elements of a list property; JSDoc rows are
// children of the documented node. Invalid indexes give 0, '' or no nodes.

const node_offset_next = 12
const node_offset_parent = 16
const node_offset_flags = 24
const node_data_type_children = u32(0)
const node_data_type_string = u32(0x40000000)
const node_string_index_mask = u32(0x00FFFFFF)
const node_child_mask = u32(0xFF)

// SyntaxKind values of TypeScript 7.1.0-beta (dist/enums/syntaxKind.enum.js) the navigation needs.
const kind_end_of_file = u32(1)
const kind_identifier = u32(79)
const kind_private_identifier = u32(80)
const kind_first_jsdoc_node = u32(309)
const kind_jsdoc = u32(316)
const kind_jsdoc_text = u32(317)
const kind_jsdoc_link = u32(320)
const kind_jsdoc_link_code = u32(321)
const kind_jsdoc_link_plain = u32(322)
const kind_last_jsdoc_node = u32(344)
const kind_extends_keyword = u32(95)
const kind_with_keyword = u32(117)
const kind_implements_keyword = u32(118)
const kind_assert_keyword = u32(131)
const kind_heritage_clause = u32(300)
const kind_import_attributes = u32(302)

// NodeFlags.JSDoc of TypeScript 7.1.0-beta (dist/enums/nodeFlags.enum.js).
const node_flag_jsdoc = u32(4194304)

// AstTree is the node table of a file, navigated by node index (the `index` of a handle). It only
// holds the binary and offsets, so copying it is cheap.
pub struct AstTree {
pub:
	path string // path tsgo identifies the file with
mut:
	data           string
	offset_nodes   int
	count          int // rows of the node table, lists included
	string_offsets int
	string_table   int
	text_start     int // the source text of the file is data[text_start..text_end] (UTF-8)
	text_end       int
	text_ascii     bool // the text is ASCII: UTF-16 positions are byte offsets
}

// decode_source_file_tree reads the node table, the path and the source text of a file, without
// indexing the nodes by range (for files that are only navigated). It checks bounds before each
// read: a malformed binary is a protocol error, not a panic.
pub fn decode_source_file_tree(data string) !AstTree {
	if data.len < header_size {
		return error('protocol: the tsgo AST is ${data.len} bytes long, shorter than the header')
	}
	version := u32_at(data, 0) >> 24
	if version != protocol_version {
		return error('protocol: the tsgo AST uses format version ${version} and veslint reads version ${protocol_version}')
	}
	offset_nodes := int(u32_at(data, header_offset_nodes))
	if offset_nodes < header_size || offset_nodes > data.len
		|| (data.len - offset_nodes) % node_len != 0 {
		return error('protocol: invalid node table in the tsgo AST (offset ${offset_nodes}, ${data.len} bytes)')
	}
	count := (data.len - offset_nodes) / node_len
	if count <= source_file_index {
		return error('protocol: the tsgo AST has no SourceFile node')
	}
	mut tree := AstTree{
		path:           source_file_path(data, offset_nodes)!
		data:           data
		offset_nodes:   offset_nodes
		count:          count
		string_offsets: int(u32_at(data, header_offset_string_table_offsets))
		string_table:   int(u32_at(data, header_offset_string_table))
	}
	// The text of the SourceFile is a string index at the start of its extended data (its path is
	// at +8, checked by source_file_path).
	node_data := u32_at(data, offset_nodes + source_file_index * node_len + node_offset_data)
	ext := int(u32_at(data, header_offset_extended_data)) + int(node_data & node_extended_data_mask)
	text_start, text_end := tree.string_range(int(u32_at(data, ext)))
	tree.text_start = text_start
	tree.text_end = text_end
	tree.text_ascii = true
	for i in text_start .. text_end {
		if data[i] >= 0x80 {
			tree.text_ascii = false
			break
		}
	}
	return tree
}

fn (t &AstTree) valid(index int) bool {
	return index >= source_file_index && index < t.count
}

fn (t &AstTree) field(index int, offset int) u32 {
	return u32_at(t.data, t.offset_nodes + index * node_len + offset)
}

// node_kind is the SyntaxKind of a node (0xFFFFFFFF for a NodeList row).
pub fn (t &AstTree) node_kind(index int) u32 {
	if !t.valid(index) {
		return 0
	}
	return t.field(index, 0)
}

// node_flags are the NodeFlags of a node (Let, Const, Ambient…: dist/enums/nodeFlags.enum.js).
pub fn (t &AstTree) node_flags(index int) u32 {
	if !t.valid(index) {
		return 0
	}
	return t.field(index, node_offset_flags)
}

// node_parent is the parent node, skipping NodeList rows like getOrCreateNodeAtIndex; 0 for the
// SourceFile.
pub fn (t &AstTree) node_parent(index int) int {
	if !t.valid(index) {
		return 0
	}
	mut parent := int(t.field(index, node_offset_parent))
	for steps := 0; steps < t.count && parent != index && t.valid(parent)
		&& t.field(parent, 0) == kind_node_list; steps++ {
		parent = int(t.field(parent, node_offset_parent))
	}
	return if parent == index || !t.valid(parent) { 0 } else { parent }
}

// node_children are the children of a node in the order of TypeScript's forEachChild: modifiers
// (decorators included), tokens (`...`, `?`, `!`, `*`) and the other children, with the elements of
// lists inlined and JSDoc nodes skipped (see node_jsdocs). For a NodeList row, its elements. The
// nodes inside a JSDoc comment are only reachable from node_jsdocs.
pub fn (t &AstTree) node_children(index int) []int {
	if t.valid(index) && t.field(index, 0) == kind_node_list {
		return t.raw_children(index)
	}
	mut out := []int{}
	for child in t.raw_children(index) {
		kind := t.field(child, 0)
		if kind == kind_node_list {
			out << t.raw_children(child)
		} else if kind != kind_jsdoc {
			out << child
		}
	}
	return out
}

// node_jsdocs are the JSDoc comments of a node (TypeScript's `node.jsDoc`), in order.
pub fn (t &AstTree) node_jsdocs(index int) []int {
	return t.raw_children(index).filter(t.field(it, 0) == kind_jsdoc)
}

// raw_children are the rows under a node (NodeList rows included) or, for a NodeList, its
// elements.
fn (t &AstTree) raw_children(index int) []int {
	mut out := []int{}
	if !t.valid(index) {
		return out
	}
	if t.field(index, 0) == kind_node_list {
		if t.field(index, node_offset_data) == 0 {
			return out
		}
	} else if !t.valid(index + 1) || int(t.field(index + 1, node_offset_parent)) != index {
		return out
	}
	mut child := index + 1
	for steps := 0; steps < t.count && t.valid(child); steps++ {
		out << child
		child = int(t.field(child, node_offset_next))
		if child == 0 {
			break
		}
	}
	return out
}

// node_child is the child of a node in a property of its SyntaxKind (child_properties: 'name',
// 'type', 'initializer', 'constraint', 'defaultType', 'members'…), like RemoteNode.getNamedChild;
// 0 if the node does not have it. A list property gives its NodeList row, whose elements are its
// node_children. A node whose data is a string or extended data (a JSDoc link, the SourceFile) has
// no child mask: like getChildAtOrder, all its properties count as present, in order.
pub fn (t &AstTree) node_child(index int, property string) int {
	if !t.valid(index) {
		return 0
	}
	properties := child_properties[t.field(index, 0)] or { return 0 }
	order := properties.index(property)
	if order < 0 {
		return 0
	}
	data := t.field(index, node_offset_data)
	mask := if data & node_data_type_mask == node_data_type_children {
		data & node_child_mask
	} else {
		node_child_mask
	}
	if mask & (u32(1) << order) == 0 {
		return 0
	}
	// Children are stored in property order, without the absent ones.
	mut child := index + 1
	for i in 0 .. order {
		if mask & (u32(1) << i) != 0 {
			child = int(t.field(child, node_offset_next))
			if !t.valid(child) {
				return 0
			}
		}
	}
	// Without a mask the row may not be a child (a property the node does not have).
	return if t.valid(child) && int(t.field(child, node_offset_parent)) == index {
		child
	} else {
		0
	}
}

// node_text is the text of an Identifier, a PrivateIdentifier, a JSDocText or the text of a JSDoc
// link (after its name: JSDocLink, JSDocLinkCode, JSDocLinkPlain), like RemoteNode.text; '' for
// other nodes.
pub fn (t &AstTree) node_text(index int) string {
	kind := t.node_kind(index)
	if kind !in [kind_identifier, kind_private_identifier, kind_jsdoc_text, kind_jsdoc_link,
		kind_jsdoc_link_code, kind_jsdoc_link_plain] {
		return ''
	}
	data := t.field(index, node_offset_data)
	if data & node_data_type_mask != node_data_type_string {
		return ''
	}
	first, last := t.string_range(int(data & node_string_index_mask))
	return t.data[first..last]
}

// node_token is the keyword of a HeritageClause (ExtendsKeyword or ImplementsKeyword) or of an
// ImportAttributes (WithKeyword or AssertKeyword), like RemoteNode.token; 0 for other nodes.
pub fn (t &AstTree) node_token(index int) u32 {
	kind := t.node_kind(index)
	if kind != kind_heritage_clause && kind != kind_import_attributes {
		return 0
	}
	data := t.field(index, node_offset_data)
	if kind == kind_heritage_clause {
		return if (data >> 24) & 1 != 0 { kind_implements_keyword } else { kind_extends_keyword }
	}
	return if (data >> 25) & 1 != 0 { kind_assert_keyword } else { kind_with_keyword }
}

// Kinds of the import and export nodes that may be type-only.
const kind_import_equals_declaration = u32(273)
const kind_import_clause = u32(275)
const kind_namespace_import = u32(276)
const kind_import_specifier = u32(278)
const kind_export_declaration = u32(280)
const kind_namespace_export = u32(282)
const kind_export_specifier = u32(283)

// node_is_type_only is the `isTypeOnly` of an ImportEqualsDeclaration, an ImportSpecifier, an
// ExportDeclaration or an ExportSpecifier, and for an ImportClause whether its phase modifier is
// `type` (RemoteNode.isTypeOnly and RemoteNode.phaseModifier).
fn (t &AstTree) node_is_type_only(index int) bool {
	data := t.field(index, node_offset_data)
	return match t.node_kind(index) {
		kind_import_clause {
			(data >> 24) & 3 == 1
		}
		kind_import_equals_declaration, kind_import_specifier, kind_export_declaration,
		kind_export_specifier {
			(data >> 24) & 1 != 0
		}
		else {
			false
		}
	}
}

// is_type_only_import_or_export ports ts.isTypeOnlyImportOrExportDeclaration: the node is an
// import or an export that only brings or gives a type (`import type`, `export type`, or a
// specifier with `type`).
pub fn (t &AstTree) is_type_only_import_or_export(index int) bool {
	if !t.valid(index) {
		return false
	}
	return match t.node_kind(index) {
		kind_import_specifier, kind_export_specifier {
			// The specifier, or the clause or the declaration its list is in.
			t.node_is_type_only(index)
				|| t.node_is_type_only(t.node_parent(t.node_parent(index)))
		}
		kind_namespace_import, kind_namespace_export {
			t.node_is_type_only(t.node_parent(index))
		}
		kind_import_clause, kind_import_equals_declaration {
			t.node_is_type_only(index)
		}
		else {
			false
		}
	}
}

// node_handle is the handle of a node ("index.kind.path"), which tsgo accepts as a location.
pub fn (t &AstTree) node_handle(index int) string {
	return '${index}.${t.node_kind(index)}.${t.path}'
}

// string_range is the byte range of a string of the table in `data` (empty when out of bounds).
fn (t &AstTree) string_range(index int) (int, int) {
	entry := t.string_offsets + index * 4
	if index < 0 || t.string_offsets < header_size || entry + 8 > t.offset_nodes {
		return 0, 0
	}
	first := t.string_table + int(u32_at(t.data, entry))
	last := t.string_table + int(u32_at(t.data, entry + 4))
	if first < header_size || last < first || last > t.offset_nodes {
		return 0, 0
	}
	return first, last
}

// The literals whose text is in their extended data (TypeScript 7.1.0-beta's SyntaxKind):
// NumericLiteral, BigIntLiteral, StringLiteral, RegularExpressionLiteral,
// NoSubstitutionTemplateLiteral, TemplateHead, TemplateMiddle and TemplateTail.
const literal_kinds = [u32(8), 9, 10, 13, 14, 15, 16, 17]

// node_literal_text is the `text` of a literal (a string, a number, a BigInt, a regular
// expression, a template without substitutions, or a part of a template), like RemoteNode.text:
// the value of a string, without its quotes and with its escapes resolved, or the number as
// TypeScript writes it; '' for other nodes.
pub fn (t &AstTree) node_literal_text(index int) string {
	if t.node_kind(index) !in literal_kinds {
		return ''
	}
	data := t.field(index, node_offset_data)
	ext := int(u32_at(t.data, header_offset_extended_data)) + int(data & node_extended_data_mask)
	if ext < header_size || ext + 4 > t.data.len {
		return ''
	}
	first, last := t.string_range(int(u32_at(t.data, ext)))
	return t.data[first..last]
}

// node_is_export_equals is the `isExportEquals` of an ExportAssignment (`export =`, not `export
// default`), like RemoteNode.isExportEquals.
pub fn (t &AstTree) node_is_export_equals(index int) bool {
	return t.node_kind(index) == 279 && (t.field(index, node_offset_data) >> 24) & 1 != 0
}

// node_end_byte is the byte offset in the source text of the file where a node ends (its `end`,
// where ESLint's node ends too); -1 for an invalid node.
pub fn (t &AstTree) node_end_byte(index int) int {
	if !t.valid(index) {
		return -1
	}
	end := int(i32(t.field(index, node_offset_end)))
	if end < 0 {
		return -1
	}
	return t.text_byte(end) - t.text_start
}

// node_token_start is the byte offset in the source text of the file where a node starts without
// its leading trivia (TypeScript's getStart(), where ESLint reports the node); -1 for an invalid
// node.
pub fn (t &AstTree) node_token_start(index int) int {
	if !t.valid(index) {
		return -1
	}
	kind := t.field(index, 0)
	pos := int(i32(t.field(index, node_offset_pos)))
	end := int(i32(t.field(index, node_offset_end)))
	if pos < 0 || end < pos {
		return -1
	}
	start_byte := t.text_byte(pos)
	end_byte := t.text_byte(end)
	if (pos == end && kind != kind_end_of_file) || end_byte < start_byte {
		return start_byte - t.text_start
	}
	is_jsdoc := kind >= kind_first_jsdoc_node && kind <= kind_last_jsdoc_node
	in_jsdoc := t.field(index, node_offset_flags) & node_flag_jsdoc != 0
	return t.skip_trivia(start_byte, end_byte, is_jsdoc, in_jsdoc && !is_jsdoc) - t.text_start
}

// node_source_text is the source text of a node like TypeScript's getText(): from its start
// without the leading trivia (getTokenPosOfNode without JSDoc) to its end.
pub fn (t &AstTree) node_source_text(index int) string {
	if !t.valid(index) {
		return ''
	}
	kind := t.field(index, 0)
	pos := int(i32(t.field(index, node_offset_pos)))
	end := int(i32(t.field(index, node_offset_end)))
	if pos < 0 || end < pos {
		return ''
	}
	// A missing node (no width) does not skip trivia.
	if pos == end && kind != kind_end_of_file {
		return ''
	}
	start_byte := t.text_byte(pos)
	end_byte := t.text_byte(end)
	if end_byte < start_byte {
		return ''
	}
	is_jsdoc := kind >= kind_first_jsdoc_node && kind <= kind_last_jsdoc_node
	in_jsdoc := t.field(index, node_offset_flags) & node_flag_jsdoc != 0
	token_start := t.skip_trivia(start_byte, end_byte, is_jsdoc, in_jsdoc && !is_jsdoc)
	return t.data[token_start..end_byte]
}

// text_byte converts a UTF-16 position of the source text into an offset of `data`.
fn (t &AstTree) text_byte(units int) int {
	if t.text_ascii {
		return if units > t.text_end - t.text_start { t.text_end } else { t.text_start + units }
	}
	mut count := 0
	mut i := t.text_start
	for i < t.text_end && count < units {
		b := t.data[i]
		count += if b >= 0xF0 { 2 } else { 1 }
		i += utf8_char_len(b)
	}
	return if i > t.text_end { t.text_end } else { i }
}

fn utf8_char_len(b u8) int {
	return if b < 0x80 {
		1
	} else if b >= 0xF0 {
		4
	} else if b >= 0xE0 {
		3
	} else if b >= 0xC0 {
		2
	} else {
		1
	}
}

// skip_trivia ports TypeScript's skipTrivia (dist/ast/scanner.js of 7.0.2) on the UTF-8 text, from
// byte `from` up to `limit`: whitespace, line breaks, comments (unless stop_at_comments), conflict
// markers and, at the start of the file, a `#!` line.
fn (t &AstTree) skip_trivia(from int, limit int, stop_at_comments bool, in_jsdoc bool) int {
	text := t.data
	mut pos := from
	mut can_consume_star := false
	for pos < limit {
		ch := text[pos]
		match ch {
			`\r`, `\n` {
				if ch == `\r` && pos + 1 < limit && text[pos + 1] == `\n` {
					pos++
				}
				pos++
				can_consume_star = in_jsdoc
				continue
			}
			`\t`, 0x0B, 0x0C, ` ` {
				pos++
				continue
			}
			`/` {
				if stop_at_comments || pos + 1 >= limit {
					return pos
				}
				if text[pos + 1] == `/` {
					pos += 2
					for pos < limit && t.line_break_len(pos) == 0 {
						pos++
					}
					can_consume_star = false
					continue
				}
				if text[pos + 1] == `*` {
					pos += 2
					for pos < limit {
						if text[pos] == `*` && pos + 1 < limit && text[pos + 1] == `/` {
							pos += 2
							break
						}
						pos++
					}
					can_consume_star = false
					continue
				}
				return pos
			}
			`<`, `|`, `=`, `>` {
				if t.is_conflict_marker(pos, limit) {
					pos = t.scan_conflict_marker(pos, limit)
					can_consume_star = false
					continue
				}
				return pos
			}
			`#` {
				if pos == t.text_start && pos + 1 < limit && text[pos + 1] == `!` {
					pos += 2
					for pos < limit && t.line_break_len(pos) == 0 {
						pos++
					}
					continue
				}
				return pos
			}
			`*` {
				if can_consume_star {
					pos++
					can_consume_star = false
					continue
				}
				return pos
			}
			else {
				if ch >= 0x80 {
					len := t.unicode_space_len(pos, limit)
					if len > 0 {
						pos += len
						continue
					}
				}
				return pos
			}
		}
	}
	return pos
}

// line_break_len is the length in bytes of the line break at `pos` (\n, \r, U+2028 or U+2029), or 0.
fn (t &AstTree) line_break_len(pos int) int {
	ch := t.data[pos]
	if ch == `\n` || ch == `\r` {
		return 1
	}
	if ch == 0xE2 && pos + 2 < t.text_end && t.data[pos + 1] == 0x80
		&& (t.data[pos + 2] == 0xA8 || t.data[pos + 2] == 0xA9) {
		return 3
	}
	return 0
}

// unicode_space_len is the length in bytes of the non-ASCII character at `pos` if it is whitespace
// or a line break for TypeScript (isWhiteSpaceLike), or 0.
fn (t &AstTree) unicode_space_len(pos int, limit int) int {
	len := utf8_char_len(t.data[pos])
	if pos + len > limit || len < 2 {
		return 0
	}
	mut r := u32(t.data[pos] & (0xFF >> (len + 1)))
	for i in 1 .. len {
		r = (r << 6) | u32(t.data[pos + i] & 0x3F)
	}
	return if r == 0xA0 || r == 0x85 || r == 0x1680 || (r >= 0x2000 && r <= 0x200B) || r == 0x202F
		|| r == 0x205F || r == 0x3000 || r == 0xFEFF || r == 0x2028 || r == 0x2029 {
		len
	} else {
		0
	}
}

// is_conflict_marker ports isConflictMarkerTrivia: seven `<`, `=`, `>` or `|` at the start of a line
// (`<` and `>` followed by a space).
fn (t &AstTree) is_conflict_marker(pos int, limit int) bool {
	text := t.data
	if pos > t.text_start {
		prev := text[pos - 1]
		at_line_start := prev == `\n` || prev == `\r` || (pos - 3 >= t.text_start
			&& text[pos - 3] == 0xE2 && text[pos - 2] == 0x80 && (prev == 0xA8 || prev == 0xA9))
		if !at_line_start {
			return false
		}
	}
	ch := text[pos]
	if pos + 6 >= limit {
		return false
	}
	for i in 1 .. 7 {
		if text[pos + i] != ch {
			return false
		}
	}
	if ch == `|` || ch == `=` {
		return true
	}
	return pos + 7 < limit && text[pos + 7] == ` `
}

// scan_conflict_marker ports scanConflictMarkerTrivia.
fn (t &AstTree) scan_conflict_marker(from int, limit int) int {
	text := t.data
	mut pos := from
	ch := text[pos]
	if ch == `<` || ch == `>` {
		for pos < limit && t.line_break_len(pos) == 0 {
			pos++
		}
		return pos
	}
	pos += 7
	for pos < limit {
		c := text[pos]
		if (c == `=` || c == `>`) && t.is_conflict_marker(pos, limit) {
			break
		}
		pos++
	}
	return pos
}
