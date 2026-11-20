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

// SourceFileAst indexes the nodes of a file by their range (pos, end). In preorder the `pos` of
// the nodes never decreases (a child starts where its parent starts or later, a sibling after the
// previous one), so the nodes that start at a unit are together in the table, the outer ones
// first: `first` gives, for each UTF-16 unit, the first node that starts there (0 for none: the
// SourceFile is node 1), and the nodes of a range are walked from the innermost (the last one) to
// the outermost. It is an array of plain numbers written in order, which the collector does not
// scan, instead of a map with an entry per node (a few for each byte of the file). When the
// positions are not in order, `innermost` gives the last node of the table with a range and
// `outer` the node with the same range before each node (-1 when there is none).
pub struct SourceFileAst {
pub:
	path  string  // path tsgo identifies the file with
	nodes int     // nodes of the table, not counting lists
	tree  AstTree // the table, to navigate it
mut:
	ordered   bool
	first     []u32
	innermost map[u64]int
	outer     []int
}

fn range_key(pos int, end int) u64 {
	return (u64(u32(pos)) << 32) | u64(u32(end))
}

// node returns the innermost node with exactly that range or, if `kind` is not 0, the innermost
// one of that SyntaxKind.
fn (a &SourceFileAst) node(pos int, end int, kind u32) ?AstNode {
	if !a.ordered {
		mut i := a.innermost[range_key(pos, end)] or { return none }
		for i >= 0 {
			node_kind := u32_at(a.tree.data, a.tree.offset_nodes + i * node_len)
			if kind == 0 || node_kind == kind {
				return AstNode{
					index: i
					kind:  node_kind
				}
			}
			i = a.outer[i]
		}
		return none
	}
	if pos < 0 || pos >= a.first.len {
		return none
	}
	start := int(a.first[pos])
	if start == 0 {
		return none
	}
	data := a.tree.data
	// The last node that starts at `pos` (the lists and the nodes without a range between them
	// are not indexed).
	mut last := start
	for i in start + 1 .. a.tree.count {
		base := a.tree.offset_nodes + i * node_len
		if u32_at(data, base) == kind_node_list {
			continue
		}
		node_pos := int(i32(u32_at(data, base + node_offset_pos)))
		node_end := int(i32(u32_at(data, base + node_offset_end)))
		if node_pos < 0 || node_end < node_pos {
			continue
		}
		if node_pos != pos {
			break
		}
		last = i
	}
	for i := last; i >= start; i-- {
		base := a.tree.offset_nodes + i * node_len
		node_kind := u32_at(data, base)
		if node_kind == kind_node_list {
			continue
		}
		node_pos := int(i32(u32_at(data, base + node_offset_pos)))
		node_end := int(i32(u32_at(data, base + node_offset_end)))
		if node_pos != pos || node_end != end {
			continue
		}
		if kind == 0 || node_kind == kind {
			return AstNode{
				index: i
				kind:  node_kind
			}
		}
	}
	return none
}

// handle returns the handle of that node (see node).
pub fn (a &SourceFileAst) handle(pos int, end int, kind u32) ?string {
	node := a.node(pos, end, kind)?
	// Written once into room of its exact size: the interpolation made a string of each number
	// and then the handle, for every node a lint asks about.
	mut b := []u8{cap: 24 + a.path.len}
	push_decimal(mut b, node.index)
	b << `.`
	push_decimal(mut b, int(node.kind))
	b << `.`
	push_text(mut b, a.path)
	return text_of(mut b)
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
	// Whether the positions of the nodes with a range never decrease in the table, and the
	// largest one.
	mut ordered := true
	mut previous := 0
	mut nodes := 0
	for i in source_file_index .. tree.count {
		base := tree.offset_nodes + i * node_len
		if u32_at(data, base) == kind_node_list {
			continue
		}
		pos := int(i32(u32_at(data, base + node_offset_pos)))
		end := int(i32(u32_at(data, base + node_offset_end)))
		if pos < 0 || end < pos {
			continue
		}
		if pos < previous {
			ordered = false
		}
		previous = pos
		nodes++
	}
	if ordered {
		mut first := []u32{len: previous + 1}
		mut at := -1
		for i in source_file_index .. tree.count {
			base := tree.offset_nodes + i * node_len
			if u32_at(data, base) == kind_node_list {
				continue
			}
			pos := int(i32(u32_at(data, base + node_offset_pos)))
			end := int(i32(u32_at(data, base + node_offset_end)))
			if pos < 0 || end < pos {
				continue
			}
			if pos != at {
				first[pos] = u32(i)
				at = pos
			}
		}
		return SourceFileAst{
			path:    tree.path
			nodes:   nodes
			tree:    tree
			ordered: true
			first:   first
		}
	}
	mut innermost := map[u64]int{}
	// V's maps grow by an eighth at a time: the room for every node at once.
	innermost.reserve(u32(tree.count))
	mut outer := []int{len: tree.count, init: -1}
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
		key := range_key(pos, end)
		outer[i] = innermost[key] or { -1 }
		innermost[key] = i
	}
	return SourceFileAst{
		path:      tree.path
		nodes:     nodes
		tree:      tree
		innermost: innermost
		outer:     outer
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
