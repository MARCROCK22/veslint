module tsgo

import json2

// Symbols by reference (TypeScript 7.1.0-beta: dist/api/proto.generated.d.ts and
// dist/api/sync/api.js). tsgo names a symbol with a SymbolReference: the symbols of the binder of
// a file by the descriptor of that file (SymbolOwnerKind File), and those the checker makes (the
// properties of a union, of a mapped type…) by their snapshot and project (SymbolOwnerKind
// Snapshot). Inside other responses (the symbol of a type, the parent of a symbol, the parameters
// of a signature) it sends a CompactSymbolReference: the id and the node id of the file, without
// the descriptor. A request that names a symbol takes its full reference.
//
// The rules keep an int per symbol: the client interns every reference it receives (SymbolTable)
// and sends the full one back when a request names that int. The full and the compact references
// of a symbol get the same int, so the rules can compare them.

// SymbolOwnerKind.File; Snapshot is 1.
const symbol_owner_file = 0

// SourceFileDescriptor identifies a version of a program file, which owns the symbols of its
// binder.
pub struct SourceFileDescriptor {
pub:
	file_name         string @[json: 'fileName']
	path              string
	content_hash      string @[json: 'contentHash']
	parse_options_key string @[json: 'parseOptionsKey']
	script_kind       int    @[json: 'scriptKind']
	node_id           string @[json: 'nodeId']
}

// SymbolReference is how tsgo names a symbol: kind 0 (File) with its file, kind 1 (Snapshot) with
// its snapshot and project. The ids of the symbols of the checker do not fit in 32 bits.
pub struct SymbolReference {
pub:
	kind     int
	file     SourceFileDescriptor
	snapshot int
	project  string
	id       i64
}

// CompactSymbolReference is a symbol inside another response: its id and the node id of its file
// ('' for a symbol of the snapshot of the response). Both are empty when the response has none.
pub struct CompactSymbolReference {
pub:
	id   i64
	file string
}

// WholeReference is what a request needs to name a symbol whose full reference arrived: the node
// id of its file, whose descriptor SymbolTable keeps once for all the symbols of the file, or its
// snapshot and project.
struct WholeReference {
	kind     int
	node_id  string
	snapshot int
	project  string
	id       i64
}

// SymbolTable interns the references tsgo sends: an int per symbol (from 1, so 0 is no symbol),
// what its full reference needs to send it back (none while only compact references of it
// arrived) and the newest snapshot it arrived in, to forget it once that snapshot is released.
struct SymbolTable {
mut:
	ids    map[string]int
	keys   map[int]string
	wholes map[int]WholeReference
	// The descriptors of the files that own the symbols, as JSON, by node id.
	files    map[string]string
	last_use map[int]int
	next     int
}

fn file_symbol_key(node_id string, id i64) string {
	return 'f${node_id}:${id}'
}

fn snapshot_symbol_key(snapshot int, id i64) string {
	return 's${snapshot}:${id}'
}

fn (mut t SymbolTable) intern(key string, snapshot int) int {
	if id := t.ids[key] {
		if snapshot > t.last_use[id] {
			t.last_use[id] = snapshot
		}
		return id
	}
	t.next++
	t.ids[key] = t.next
	t.keys[t.next] = key
	t.last_use[t.next] = snapshot
	return t.next
}

// intern_reference gives the int of a full reference that arrived in a request of `snapshot`.
fn (mut t SymbolTable) intern_reference(r SymbolReference, snapshot int) int {
	key := if r.kind == symbol_owner_file {
		file_symbol_key(r.file.node_id, r.id)
	} else {
		snapshot_symbol_key(r.snapshot, r.id)
	}
	id := t.intern(key, snapshot)
	if id !in t.wholes {
		if r.kind == symbol_owner_file && r.file.node_id !in t.files {
			t.files[r.file.node_id] = json2.encode(r.file)
		}
		t.wholes[id] = WholeReference{
			kind:     r.kind
			node_id:  r.file.node_id
			snapshot: r.snapshot
			project:  r.project
			id:       r.id
		}
	}
	return id
}

// intern_compact gives the int of a compact reference that arrived in a request of `snapshot`, 0
// when the response has none.
fn (mut t SymbolTable) intern_compact(r CompactSymbolReference, snapshot int) int {
	if r.id == 0 && r.file == '' {
		return 0
	}
	key := if r.file != '' {
		file_symbol_key(r.file, r.id)
	} else {
		snapshot_symbol_key(snapshot, r.id)
	}
	return t.intern(key, snapshot)
}

// reference gives the JSON of the full reference of a symbol, as tsgo reads it in a request.
fn (t &SymbolTable) reference(id int) !string {
	if whole := t.wholes[id] {
		if whole.kind == symbol_owner_file {
			return '{"kind":${whole.kind},"file":${t.files[whole.node_id]},"id":${whole.id}}'
		}
		project := if whole.project == '' {
			''
		} else {
			',"project":${json2.encode(whole.project)}'
		}
		return '{"kind":${whole.kind},"snapshot":${whole.snapshot}${project},"id":${whole.id}}'
	}
	if id in t.keys {
		return error('symbol ${id} only arrived as a compact reference; tsgo needs the whole symbol before a request names it')
	}
	return error('symbol ${id} is unknown to the client (0 is no symbol, and a released snapshot forgets its symbols)')
}

// forget drops the symbols last seen in `snapshot` or before: once it is released, the requests
// are of newer snapshots, which intern again what they receive.
fn (mut t SymbolTable) forget(snapshot int) {
	mut stale := []int{}
	for id, last in t.last_use {
		if last <= snapshot {
			stale << id
		}
	}
	for id in stale {
		t.ids.delete(t.keys[id])
		t.keys.delete(id)
		t.wholes.delete(id)
		t.last_use.delete(id)
	}
	if stale.len == 0 {
		return
	}
	// The descriptors no symbol left needs.
	mut needed := map[string]bool{}
	for _, whole in t.wholes {
		if whole.kind == symbol_owner_file {
			needed[whole.node_id] = true
		}
	}
	for node_id in t.files.keys() {
		if node_id !in needed {
			t.files.delete(node_id)
		}
	}
}

// intern_symbol turns the references of a symbol tsgo sent in a request of `snapshot` into the
// ints of SymbolTable. A protocol `null` stays the null symbol.
fn (mut c Client) intern_symbol(snapshot int, s SymbolResponse) SymbolResponse {
	if s.reference.kind == symbol_owner_file && s.reference.file.node_id == '' {
		return SymbolResponse{}
	}
	return SymbolResponse{
		...s
		id:            c.symbols.intern_reference(s.reference, snapshot)
		parent:        c.symbols.intern_compact(s.parent_reference, snapshot)
		export_symbol: c.symbols.intern_compact(s.export_symbol_reference, snapshot)
	}
}

fn (mut c Client) intern_symbols(snapshot int, symbols []SymbolResponse) []SymbolResponse {
	return symbols.map(c.intern_symbol(snapshot, it))
}

// intern_type turns the symbols of a type tsgo sent in a request of `snapshot` into the ints of
// SymbolTable.
fn (mut c Client) intern_type(snapshot int, t TypeResponse) TypeResponse {
	if t.symbol_reference.id == 0 && t.symbol_reference.file == ''
		&& t.alias_symbol_reference.id == 0 && t.alias_symbol_reference.file == '' {
		return t
	}
	return TypeResponse{
		...t
		symbol:       c.symbols.intern_compact(t.symbol_reference, snapshot)
		alias_symbol: c.symbols.intern_compact(t.alias_symbol_reference, snapshot)
	}
}

fn (mut c Client) intern_types(snapshot int, types []TypeResponse) []TypeResponse {
	return types.map(c.intern_type(snapshot, it))
}

// intern_signature turns the `this` parameter of a signature into an int of SymbolTable.
fn (mut c Client) intern_signature(snapshot int, s SignatureResponse) SignatureResponse {
	if s.this_parameter_reference.id == 0 && s.this_parameter_reference.file == '' {
		return s
	}
	return SignatureResponse{
		...s
		this_parameter: c.symbols.intern_compact(s.this_parameter_reference, snapshot)
	}
}

// symbol_params are the params of a method of the checker on a symbol (CheckerSymbolParams,
// GetTypeOfSymbolParams): the snapshot, the project and the full reference.
fn (c &Client) symbol_params(snapshot int, project string, symbol_id int) !string {
	return '{"snapshot":${snapshot},"project":${json2.encode(project)},"symbol":${c.symbols.reference(symbol_id)!}}'
}

// symbol_property_params are those of a property of a symbol (GetSymbolPropertyParams): the
// reference alone.
fn (c &Client) symbol_property_params(symbol_id int) !string {
	return '{"symbol":${c.symbols.reference(symbol_id)!}}'
}

// symbols_seen gives how many symbols the client has interned (for the tests).
fn (c &Client) symbols_seen() int {
	return c.symbols.ids.len
}
