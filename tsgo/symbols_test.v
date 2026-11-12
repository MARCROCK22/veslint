module tsgo

import os
import time

// The interning of symbol references (symbols.v).

const symbols_test_file = SourceFileDescriptor{
	file_name:         '/p/a.ts'
	path:              '/p/a.ts'
	content_hash:      'ff92d5ac'
	parse_options_key: '2'
	script_kind:       3
	node_id:           '77'
}

fn test_full_and_compact_references_share_the_int() {
	mut t := SymbolTable{}
	box := t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 1 }, 1)
	assert box == 1
	// The same symbol again, and through a compact reference of its file.
	assert t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 1 }, 1) == box
	assert t.intern_compact(CompactSymbolReference{ id: 1, file: '77' }, 1) == box
	// The same id in another file, or owned by the snapshot, is another symbol.
	assert t.intern_compact(CompactSymbolReference{ id: 1, file: '78' }, 1) !in [0, box]
	union_property := t.intern_reference(SymbolReference{
		kind:     1
		snapshot: 1
		project:  '/p/tsconfig.json'
		id:       281474976710663
	}, 1)
	assert union_property !in [0, box]
	assert t.intern_compact(CompactSymbolReference{ id: 281474976710663 }, 1) == union_property
	// No reference is no symbol.
	assert t.intern_compact(CompactSymbolReference{}, 1) == 0
	// The descriptor of a file is kept once, for all its symbols.
	assert t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 2 }, 1) !in [0, box]
	assert t.files.len == 1
}

fn test_reference_json() {
	mut t := SymbolTable{}
	file_owned := t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 3 }, 1)
	assert t.reference(file_owned) or { panic(err) } == '{"kind":0,"file":{"fileName":"/p/a.ts","path":"/p/a.ts","contentHash":"ff92d5ac","parseOptionsKey":"2","scriptKind":3,"nodeId":"77"},"id":3}'
	snapshot_owned := t.intern_reference(SymbolReference{
		kind:     1
		snapshot: 2
		project:  '/p/"q"/tsconfig.json'
		id:       281474976710663
	}, 2)
	assert t.reference(snapshot_owned) or { panic(err) } == '{"kind":1,"snapshot":2,"project":"/p/\\"q\\"/tsconfig.json","id":281474976710663}'
	without_project := t.intern_reference(SymbolReference{ kind: 1, snapshot: 2, id: 9 }, 2)
	assert t.reference(without_project) or { panic(err) } == '{"kind":1,"snapshot":2,"id":9}'
	// A symbol only seen in a compact reference cannot be named in a request yet.
	compact := t.intern_compact(CompactSymbolReference{ id: 5, file: '77' }, 2)
	if _ := t.reference(compact) {
		assert false
	} else {
		assert err.msg().contains('compact reference')
	}
	// Once the full reference arrives, it can.
	assert t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 5 }, 2) == compact
	assert t.reference(compact) or { panic(err) }.ends_with('"id":5}')
	if _ := t.reference(1000) {
		assert false
	} else {
		assert err.msg().contains('unknown')
	}
}

fn test_forget_drops_what_a_released_snapshot_saw_last() {
	mut t := SymbolTable{}
	old := t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 1 }, 1)
	kept := t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 2 }, 1)
	// Seen again in snapshot 2: it outlives snapshot 1.
	assert t.intern_compact(CompactSymbolReference{ id: 2, file: '77' }, 2) == kept
	t.forget(1)
	if _ := t.reference(old) {
		assert false
	}
	assert t.reference(kept) or { panic(err) }.ends_with('"id":2}')
	// A forgotten symbol that arrives again gets a new int.
	again := t.intern_reference(SymbolReference{ kind: 0, file: symbols_test_file, id: 1 }, 2)
	assert again !in [old, kept]
	t.forget(2)
	assert t.ids.len == 0 && t.keys.len == 0 && t.wholes.len == 0 && t.last_use.len == 0
	assert t.files.len == 0
}

const symbols_test_source = 'interface Box<T> { value: T }
declare const box: Box<number>;
type U = { a: 1 } | { a: 2 };
declare const u: U;
'

// Against the real tsgo: the symbol of a type (a compact reference) is the one symbol_of_type
// gives whole, a symbol of the checker (a property of a union, whose id does not fit in 32 bits)
// can be named in a request, and a released snapshot forgets its symbols.
fn test_symbol_references_with_tsgo() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-symbols-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	file := os.join_path(dir, 'a.ts')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(file, symbols_test_source) or { panic(err) }
	mut c := start(bin, dir, 20 * time.second) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	project := snap.projects[0].id
	s := snap.snapshot
	box_at := symbols_test_source.index('box:') or { panic('no box') }
	u_at := symbols_test_source.index('u:') or { panic('no u') }
	types := c.types_at(s, project, file, [box_at, u_at]) or { panic(err) }
	box, u := types[0], types[1]
	assert box.symbol != 0
	box_symbol := c.symbol_of_type(s, project, box.id) or { panic(err) }
	assert box_symbol.name == 'Box' && box_symbol.id == box.symbol
	// `U` is the alias symbol of the union.
	assert u.alias_symbol != 0 && u.symbol == 0
	alias := c.alias_symbol_of_type(s, project, u.id) or { panic(err) }
	assert alias.name == 'U' && alias.id == u.alias_symbol
	properties := c.properties_of_type(s, project, u.id) or { panic(err) }
	assert properties.len == 1 && properties[0].name == 'a'
	// A property of a union is a symbol of the checker (CheckFlags.SyntheticProperty).
	assert properties[0].check_flags & 2 != 0
	a_type := c.type_of_symbol(s, project, properties[0].id) or { panic(err) }
	assert a_type.flags & 134217728 != 0 // TypeFlags.Union (1 << 27 in tsgo)
	assert c.type_to_string(s, project, a_type.id) or { panic(err) } == '1 | 2'
	assert c.symbols_seen() > 0
	c.release_snapshot(s) or { panic(err) }
	assert c.symbols_seen() == 0
	if _ := c.type_of_symbol(s, project, properties[0].id) {
		assert false
	} else {
		assert err.msg().contains('unknown')
	}
}
