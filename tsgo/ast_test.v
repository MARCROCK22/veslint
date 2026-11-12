module tsgo

import os
import time

// With a real tsgo: the path comes from the binary, ranges are in UTF-16 (three emoji before) and
// tsgo accepts the handle() identifiers in getTypeAtLocations.
fn test_source_file_ast_names_nodes_that_tsgo_accepts() {
	dir := os.join_path(@VMODROOT, 'tests', 'fixtures')
	file := os.join_path(dir, 'emoji.ts') // const s = "🎉🎉🎉"; const x = 1;
	mut client := start(os.join_path(@VMODROOT, rel_path), dir, 10 * time.second) or { panic(err) }
	defer {
		client.shutdown()
	}
	_ = client.initialize() or { panic(err) }
	snap := client.create_snapshot([os.join_path(dir, 'tsconfig.json')]) or { panic(err) }
	project := snap.projects[0].id
	ast := client.source_file_ast(snap.snapshot, project, file) or { panic(err) }
	assert ast.path == file
	assert ast.nodes > 10
	// `x` starts at unit 26 and `1` at 30; pos includes the previous space.
	x := ast.handle(25, 27, 0) or { panic('no node for `x`') }
	one := ast.handle(29, 31, 0) or { panic('no node for `1`') }
	assert ast.handle(26, 27, 0) == none
	// A node of another SyntaxKind with the same range does not count.
	assert ast.handle(29, 31, 1) == none
	types := client.types_at_locations(snap.snapshot, project, [x, one]) or { panic(err) }
	assert types.len == 2
	for t in types {
		assert client.type_to_string(snap.snapshot, project, t.id) or { panic(err) } == '1'
	}
}

fn test_decode_source_file_rejects_malformed_data() {
	assert_protocol_error('')
	mut header := []u8{len: header_size}
	// A format version other than the one veslint reads.
	header[3] = 4
	assert_protocol_error(header.bytestr())
	header[3] = u8(protocol_version)
	// No node table.
	assert_protocol_error(header.bytestr())
	// A node table that is not a multiple of 28 bytes.
	header[header_offset_nodes] = u8(header_size)
	assert_protocol_error(header.bytestr() + 'x')
	// Only node 0: the SourceFile is missing.
	assert_protocol_error(header.bytestr() + []u8{len: node_len}.bytestr())
	// SourceFile without extended data.
	assert_protocol_error(header.bytestr() + []u8{len: 2 * node_len}.bytestr())
}

// The branches of source_file_path: the SourceFile has extended data, but what it points to is
// outside the binary.
fn test_decode_source_file_rejects_bad_source_file_path() {
	// Header + 16 bytes of extended data + 8 of string offsets + 2 nodes.
	ext := header_size
	offsets := ext + 16
	nodes := offsets + 8
	mut data := []u8{len: nodes + 2 * node_len}
	data[3] = u8(protocol_version)
	put_u32(mut data, header_offset_extended_data, u32(ext))
	put_u32(mut data, header_offset_string_table_offsets, u32(offsets))
	put_u32(mut data, header_offset_string_table, u32(offsets))
	put_u32(mut data, header_offset_nodes, u32(nodes))
	source_file_data := nodes + source_file_index * node_len + node_offset_data
	// Extended data out of range.
	put_u32(mut data, source_file_data, node_data_type_extended | 0x1000)
	assert_protocol_error(data.bytestr())
	// String index outside the offset table.
	put_u32(mut data, source_file_data, node_data_type_extended)
	put_u32(mut data, ext + 8, 7)
	assert_protocol_error(data.bytestr())
	// A string that ends before it starts.
	put_u32(mut data, ext + 8, 0)
	put_u32(mut data, offsets, 4)
	put_u32(mut data, offsets + 4, 2)
	assert_protocol_error(data.bytestr())
	// And well formed: the path is string 0, empty.
	put_u32(mut data, offsets, 0)
	put_u32(mut data, offsets + 4, 0)
	ast := decode_source_file(data.bytestr()) or { panic(err) }
	assert ast.path == ''
}

fn put_u32(mut data []u8, offset int, value u32) {
	for i in 0 .. 4 {
		data[offset + i] = u8(value >> (8 * i))
	}
}

fn assert_protocol_error(data string) {
	decode_source_file(data) or {
		assert err.msg().starts_with('protocol:')
		return
	}
	assert false, 'expected a protocol error'
}

// AstTree follows TypeScript's forEachChild (modifiers and tokens included, NodeList elements
// inlined, JSDoc apart), with parents, identifier texts, children by property, NodeFlags,
// getText() and handles tsgo accepts, also in a lib file. ast_walk_expected is the output of
// forEachChild over the same file with typescript/sync (7.1.0-beta): `index kind parent=… text
// jsdoc=…`. Since 7.1 the types of `implements` and of an interface's `extends` are TypeReferences
// (185), and only a class's `extends` has an ExpressionWithTypeArguments (235).
fn test_ast_tree_navigation_matches_for_each_child() {
	dir := os.join_path(os.temp_dir(), 'veslint-ast-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	os.write_file(os.join_path(dir, 'tsconfig.json'), '{"compilerOptions":{"strict":true,"noEmit":true,"target":"es2022","lib":["es2022"]},"include":["*.ts"]}') or {
		panic(err)
	}
	file := os.join_path(dir, 'walk.ts')
	os.write_file(file, ast_walk_source) or { panic(err) }
	mut client := start(os.join_path(@VMODROOT, rel_path), dir, 10 * time.second) or { panic(err) }
	defer {
		client.shutdown()
	}
	_ = client.initialize() or { panic(err) }
	snap := client.create_snapshot([os.join_path(dir, 'tsconfig.json')]) or { panic(err) }
	project := snap.projects[0].id
	ast := client.source_file_ast(snap.snapshot, project, file) or { panic(err) }
	tree := ast.tree
	mut lines := []string{}
	walk_ast_tree(tree, 1, 0, mut lines)
	assert lines.join('\n') == ast_walk_expected
	// Children by property: a type parameter with only a constraint and one with only a default,
	// tokens and modifiers.
	assert tree.node_child(65, 'constraint') == 67
	assert tree.node_child(65, 'defaultType') == 0
	assert tree.node_child(68, 'constraint') == 0
	assert tree.node_child(68, 'defaultType') == 70
	assert tree.node_child(37, 'dotDotDotToken') == 38
	assert tree.node_child(37, 'name') == 39
	assert tree.node_child(34, 'dotDotDotToken') == 0
	assert tree.node_child(80, 'name') == 81
	assert tree.node_child(80, 'type') == 82
	assert tree.node_child(80, 'initializer') == 86
	assert tree.node_child(80, 'exclamationToken') == 0
	assert tree.node_child(91, 'exclamationToken') == 93
	assert tree.node_child(56, 'postfixToken') == 60
	assert tree.node_child(103, 'questionToken') == 105
	assert tree.node_child(100, 'questionToken') == 0
	assert tree.node_child(56, 'unknownProperty') == 0
	modifiers := tree.node_child(56, 'modifiers')
	assert tree.node_kind(modifiers) == kind_node_list
	assert tree.node_children(modifiers) == [58] // DeclareKeyword
	members := tree.node_child(3, 'members')
	assert tree.node_children(members) == [8, 18]
	// NodeFlags: Const and Let declaration lists, Ambient declarations.
	assert tree.node_flags(78) & 2 != 0
	assert tree.node_flags(89) & 1 != 0
	assert tree.node_flags(56) & 8388608 != 0
	// getText(): without leading trivia, comments or JSDoc (the file starts with an emoji).
	assert tree.node_source_text(8) == "Red = 'red'"
	assert tree.node_source_text(27) == '@logged static make(this: void, ...sizes: number[]): Box {\n    return new Box();\n  }'
	assert tree.node_source_text(37) == '...sizes: number[]'
	assert tree.node_source_text(50) == '#secret = function () {};'
	assert tree.node_source_text(56) == 'declare tag?: string;'
	assert tree.node_source_text(68) == 'B = number'
	assert tree.node_source_text(78) == 'const items: Array<string> = []'
	assert tree.node_source_text(91) == 'definite!: number'
	assert tree.node_source_text(11) == '/** @deprecated use Blue */'
	// JSDoc: the tags of a comment, their name and the texts and links of their comment.
	assert tree.node_jsdocs(108) == [114]
	tags := tree.node_children(tree.node_child(114, 'tags'))
	assert tags == [117] && tree.node_kind(117) == 326 // JSDocDeprecatedTag
	assert tree.node_text(tree.node_child(117, 'tagName')) == 'deprecated'
	parts := tree.node_children(tree.node_child(117, 'comment'))
	assert parts.map(tree.node_kind(it)) == [u32(317), 320, 317, 321, 317]
	assert parts.map(tree.node_text(it)) == ['Use ', '', ' or ', '| the items', '.']
	assert tree.node_text(tree.node_child(124, 'name')) == 'items'
	assert tree.node_children(tree.node_child(114, 'comment')).len == 0
	// Heritage clauses and import attributes: their keyword.
	assert tree.node_token(130) == 95 // `interface Named extends …`: ExtendsKeyword
	assert tree.node_children(tree.node_child(137, 'heritageClauses')) == [142, 148]
	assert tree.node_token(142) == 95
	assert tree.node_token(148) == 118 // ImplementsKeyword
	assert tree.node_children(tree.node_child(148, 'types')) == [150, 152]
	assert tree.node_token(162) == 117 // `with { … }`: WithKeyword
	assert tree.node_token(172) == 131 // `assert { … }`: AssertKeyword
	assert tree.node_token(137) == 0
	// Handles: tsgo accepts them and they name the same node.
	handle := tree.node_handle(24)
	assert handle == '24.265.${tree.path}'
	assert handle_index(handle) == 24 && handle_kind(handle) == 265 && handle_path(handle) == tree.path
	// The symbol of `Array` is declared in lib.es5.d.ts, which can be navigated too.
	symbols := client.symbols_at_locations(snap.snapshot, project, [tree.node_handle(83)]) or {
		panic(err)
	}
	assert symbols.len == 1 && symbols[0].name == 'Array'
	declaration := symbols[0].declarations[0]
	assert handle_path(declaration).ends_with('lib.es5.d.ts')
	lib := client.source_file_ast_tree(snap.snapshot, project, handle_path(declaration)) or {
		panic(err)
	}
	index := handle_index(declaration)
	assert lib.node_kind(index) == 266 // InterfaceDeclaration
	assert lib.node_parent(index) == 1
	assert lib.node_text(lib.node_child(index, 'name')) == 'Array'
	assert lib.node_source_text(index).starts_with('interface Array<T> {\n    /**')
	types := client.types_at_locations(snap.snapshot, project, [lib.node_handle(index)]) or {
		panic(err)
	}
	assert types.len == 1 && !types[0].is_null()
	// A method signature of that interface: tsgo types it and gives its signature.
	mut push := 0
	for member in lib.node_children(index) {
		if lib.node_kind(member) == 175 && lib.node_text(lib.node_child(member, 'name')) == 'push' {
			push = member
			break
		}
	}
	assert push != 0
	signature := client.signature_from_declaration(snap.snapshot, project, lib.node_handle(push)) or {
		panic(err)
	}
	assert signature.id != 0
	member_types := client.types_at_locations(snap.snapshot, project, [lib.node_handle(push)]) or {
		panic(err)
	}
	assert member_types.len == 1 && !member_types[0].is_null()
}

fn walk_ast_tree(tree AstTree, index int, depth int, mut lines []string) {
	kind := tree.node_kind(index)
	text := if kind in [kind_identifier, kind_private_identifier] {
		' ${tree.node_text(index)}'
	} else {
		''
	}
	jsdocs := tree.node_jsdocs(index)
	jsdoc := if jsdocs.len > 0 { ' jsdoc=${jsdocs.map(it.str()).join(',')}' } else { '' }
	lines << '${'  '.repeat(depth)}${index} ${kind} parent=${tree.node_parent(index)}${text}${jsdoc}'
	for child in tree.node_children(index) {
		walk_ast_tree(tree, child, depth + 1, mut lines)
	}
}

const ast_walk_source = "// 🎉 non-ASCII text before the declarations
/** Docs of the enum. */
export enum Color {
  /** @deprecated use Blue */
  Red = 'red',
  Blue = 'blue',
}
class Box {
  @logged static make(this: void, ...sizes: number[]): Box {
    return new Box();
  }
  #secret = function () {};
  declare tag?: string;
}
type Pair<A extends string, B = number> = [A, B];
const items: Array<string> = [];
let definite!: number;
declare function logged(value: unknown, context?: unknown): void;
/** @deprecated Use {@link logged} or {@linkcode items | the items}. */
declare function legacy(): void;
interface Named extends Iterable<string> {}
declare class Derived extends Array<string> implements Named, ArrayLike<string> {}
import {} from './walk' with { type: 'json' };
import {} from './walk' assert { type: 'json' };
"

const ast_walk_expected = '1 308 parent=0
  3 268 parent=1 jsdoc=21
    5 94 parent=3
    6 79 parent=3 Color
    8 307 parent=3 jsdoc=11
      9 79 parent=8 Red
      10 10 parent=8
    18 307 parent=3
      19 79 parent=18 Blue
      20 10 parent=18
  24 265 parent=1
    25 79 parent=24 Box
    27 176 parent=24
      29 172 parent=27
        30 79 parent=29 logged
      31 125 parent=27
      32 79 parent=27 make
      34 171 parent=27
        35 79 parent=34 this
        36 115 parent=34
      37 171 parent=27
        38 25 parent=37
        39 79 parent=37 sizes
        40 190 parent=37
          41 150 parent=40
      42 185 parent=27
        43 79 parent=42 Box
      44 243 parent=27
        46 255 parent=44
          47 216 parent=46
            48 79 parent=47 Box
    50 174 parent=24
      51 80 parent=50 #secret
      52 220 parent=50
        54 243 parent=52
    56 174 parent=24
      58 137 parent=56
      59 79 parent=56 tag
      60 57 parent=56
      61 154 parent=56
  62 267 parent=1
    63 79 parent=62 Pair
    65 170 parent=62
      66 79 parent=65 A
      67 154 parent=65
    68 170 parent=62
      69 79 parent=68 B
      70 150 parent=68
    71 191 parent=62
      73 185 parent=71
        74 79 parent=73 A
      75 185 parent=71
        76 79 parent=75 B
  77 245 parent=1
    78 263 parent=77
      80 262 parent=78
        81 79 parent=80 items
        82 185 parent=80
          83 79 parent=82 Array
          85 154 parent=82
        86 211 parent=80
  88 245 parent=1
    89 263 parent=88
      91 262 parent=89
        92 79 parent=91 definite
        93 53 parent=91
        94 150 parent=91
  95 264 parent=1
    97 137 parent=95
    98 79 parent=95 logged
    100 171 parent=95
      101 79 parent=100 value
      102 159 parent=100
    103 171 parent=95
      104 79 parent=103 context
      105 57 parent=103
      106 159 parent=103
    107 115 parent=95
  108 264 parent=1 jsdoc=114
    110 137 parent=108
    111 79 parent=108 legacy
    113 115 parent=108
  127 266 parent=1
    128 79 parent=127 Named
    130 300 parent=127
      132 185 parent=130
        133 79 parent=132 Iterable
        135 154 parent=132
  137 265 parent=1
    139 137 parent=137
    140 79 parent=137 Derived
    142 300 parent=137
      144 235 parent=142
        145 79 parent=144 Array
        147 154 parent=144
    148 300 parent=137
      150 185 parent=148
        151 79 parent=150 Named
      152 185 parent=148
        153 79 parent=152 ArrayLike
        155 154 parent=152
  157 274 parent=1
    158 275 parent=157
      159 277 parent=158
    161 10 parent=157
    162 302 parent=157
      164 303 parent=162
        165 79 parent=164 type
        166 10 parent=164
  167 274 parent=1
    168 275 parent=167
      169 277 parent=168
    171 10 parent=167
    172 302 parent=167
      174 303 parent=172
        175 79 parent=174 type
        176 10 parent=174
  177 1 parent=1'
