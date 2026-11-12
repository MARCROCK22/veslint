module tsgo

// Binary AST of a file according to tsgo (`getSourceFile`). veslint walks the files it lints with
// tree-sitter; it uses this tree to name nodes (getTypeAtLocation(s) takes a handle
// "index.kind.path", where the index is the position of the node in this table) and, through
// AstTree (ast_tree.v), to look at declarations in any file of the program.
//
// TypeScript 7.1.0-beta format (dist/api/node/protocol.js and node.js): a 64-byte header with
// little-endian u32 offsets (7.0.2 had 44 bytes: 7.1 adds the source file id, its lease and the
// binder data after them) and, from `offset_nodes` to the end, a table of 28-byte nodes (kind,
// pos, end, next, parent, data, flags) in preorder. `pos` and `end` are in UTF-16 units and `pos`
// includes the leading trivia, as in TypeScript.

// Format version: the high byte of the first u32 of the header (dist/api/node/encoder.js).
const protocol_version = u32(9)

const header_offset_string_table_offsets = 24
const header_offset_string_table = 28
const header_offset_extended_data = 32
const header_offset_nodes = 40
const header_size = 64
const node_len = 28
const node_offset_pos = 4
const node_offset_end = 8
const node_offset_data = 20
const kind_node_list = u32(0xFFFFFFFF)
const node_data_type_mask = u32(0xC0000000)
const node_data_type_extended = u32(0x80000000)
const node_extended_data_mask = u32(0x00FFFFFF)
const source_file_index = 1

struct AstNode {
	index int
	kind  u32
}

// SourceFileAst indexes the nodes of a file by their range (pos, end); nodes with the same range
// go from the outermost to the innermost.
pub struct SourceFileAst {
pub:
	path  string  // path tsgo identifies the file with
	nodes int     // nodes of the table, not counting lists
	tree  AstTree // the table, to navigate it
mut:
	by_range map[u64][]AstNode
}

fn range_key(pos int, end int) u64 {
	return (u64(u32(pos)) << 32) | u64(u32(end))
}

// node returns the innermost node with exactly that range or, if `kind` is not 0, the innermost
// one of that SyntaxKind.
fn (a &SourceFileAst) node(pos int, end int, kind u32) ?AstNode {
	nodes := a.by_range[range_key(pos, end)] or { return none }
	for i := nodes.len - 1; i >= 0; i-- {
		if kind == 0 || nodes[i].kind == kind {
			return nodes[i]
		}
	}
	return none
}

// handle returns the handle of that node (see node).
pub fn (a &SourceFileAst) handle(pos int, end int, kind u32) ?string {
	node := a.node(pos, end, kind)?
	return '${node.index}.${node.kind}.${a.path}'
}

// kind returns the SyntaxKind of the innermost node with that range.
pub fn (a &SourceFileAst) kind(pos int, end int) ?u32 {
	node := a.node(pos, end, 0)?
	return node.kind
}

fn u32_at(data string, offset int) u32 {
	return u32(data[offset]) | (u32(data[offset + 1]) << 8) | (u32(data[offset + 2]) << 16) | (u32(data[offset +
		3]) << 24)
}

// decode_source_file reads the node table and the path of the file (decode_source_file_tree) and
// indexes the nodes by range.
pub fn decode_source_file(data string) !SourceFileAst {
	tree := decode_source_file_tree(data)!
	mut by_range := map[u64][]AstNode{}
	mut nodes := 0
	// In preorder children come after the parent: the last node with a range is the innermost.
	for i in source_file_index .. tree.count {
		base := tree.offset_nodes + i * node_len
		kind := u32_at(data, base)
		if kind == kind_node_list {
			continue
		}
		pos := int(i32(u32_at(data, base + node_offset_pos)))
		end := int(i32(u32_at(data, base + node_offset_end)))
		if pos < 0 || end < pos {
			continue
		}
		by_range[range_key(pos, end)] << AstNode{
			index: i
			kind:  kind
		}
		nodes++
	}
	return SourceFileAst{
		path:     tree.path
		nodes:    nodes
		tree:     tree
		by_range: by_range
	}
}

// source_file_path reads the path of the SourceFile: a string index in its extended data (+8).
fn source_file_path(data string, offset_nodes int) !string {
	node_data := u32_at(data, offset_nodes + source_file_index * node_len + node_offset_data)
	if node_data & node_data_type_mask != node_data_type_extended {
		return error('protocol: the SourceFile of the tsgo AST has no extended data')
	}
	ext := int(u32_at(data, header_offset_extended_data)) + int(node_data & node_extended_data_mask)
	if ext < header_size || ext + 12 > offset_nodes {
		return error('protocol: extended data out of range in the tsgo AST')
	}
	index := int(u32_at(data, ext + 8))
	offsets := int(u32_at(data, header_offset_string_table_offsets))
	table := int(u32_at(data, header_offset_string_table))
	if offsets < header_size || offsets + (index + 2) * 4 > offset_nodes {
		return error('protocol: string index out of range in the tsgo AST')
	}
	str_start := table + int(u32_at(data, offsets + index * 4))
	end := table + int(u32_at(data, offsets + (index + 1) * 4))
	if str_start < header_size || end < str_start || end > offset_nodes {
		return error('protocol: string out of range in the tsgo AST')
	}
	return data[str_start..end]
}
