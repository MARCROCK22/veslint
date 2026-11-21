module rules

import tsgo { TypeResponse }

// NodeTable is what the rules of a file have asked tsgo about each node key (node_key: the range
// of a tree-sitter node): whether it was looked up in tsgo, whether its type was requested, the
// index (which makes its handle) and the SyntaxKind of the tsgo node found for it, and its type. One table of the keys
// (open addressing over plain numbers, which the collector does not scan) gives each key a dense
// id, and the rest is in arrays by id; the types stay in the arrays tsgo's answers were decoded
// into. Five maps by key did the same: each was grown for the nodes of a large file (every rule
// asks for tens of thousands), copying all their entries, a type of a few hundred bytes for each
// node in one of them, and that was the largest share of what a typed lint allocated.
struct NodeTable {
mut:
	// slots[h] is the id of a key plus one, 0 for an empty slot; its length is a power of two,
	// at most half full.
	slots []u32
	keys  []u64
	flags []u8
	kinds []u32 // 0 when the node has none
	// indexes[id] is the index of the tsgo node in the table of the file of `path`, valid with
	// node_has_handle: its handle is made when a rule asks for it (handle), since most of them
	// are only sent in the requests of types, which take the index (Client.types_at_nodes).
	indexes []u32
	path    string
	// The type of a node is types[type_chunk[id]][type_index[id]], with node_has_type.
	type_chunk []u32
	type_index []u32
	types      [][]TypeResponse
	// The place of each key in the groups of a resolve_new: group[id], for the call `call` when
	// group_call[id] is it.
	group      []u32
	group_call []u32
	call       u32
}

const node_attempted = u8(1) // looked up in tsgo
const node_typed = u8(2) // its type was requested
const node_has_handle = u8(4)
const node_has_type = u8(8)

@[inline]
fn node_table_hash(key u64, mask u32) u32 {
	return u32((key * u64(0x9e3779b97f4a7c15)) >> 32) & mask
}

// id gives the id of a key, -1 when the table does not have it.
fn (t &NodeTable) id(key u64) int {
	if t.slots.len == 0 {
		return -1
	}
	mask := u32(t.slots.len - 1)
	mut h := node_table_hash(key, mask)
	for {
		slot := t.slots[h]
		if slot == 0 {
			return -1
		}
		if t.keys[slot - 1] == key {
			return int(slot - 1)
		}
		h = (h + 1) & mask
	}
	return -1
}

// add gives the id of a key, which it adds if the table does not have it.
fn (mut t NodeTable) add(key u64) int {
	if 2 * (t.keys.len + 1) > t.slots.len {
		t.grow(t.keys.len + 1)
	}
	mask := u32(t.slots.len - 1)
	mut h := node_table_hash(key, mask)
	for {
		slot := t.slots[h]
		if slot == 0 {
			break
		}
		if t.keys[slot - 1] == key {
			return int(slot - 1)
		}
		h = (h + 1) & mask
	}
	id := t.keys.len
	t.slots[h] = u32(id + 1)
	t.keys << key
	t.flags << 0
	t.kinds << 0
	t.indexes << 0
	t.type_chunk << 0
	t.type_index << 0
	t.group << 0
	t.group_call << 0
	return id
}

// reserve makes room for `more` keys.
fn (mut t NodeTable) reserve(more int) {
	need := t.keys.len + more
	if 2 * need <= t.slots.len {
		return
	}
	t.grow(need)
	t.keys.ensure_cap(need)
	t.flags.ensure_cap(need)
	t.kinds.ensure_cap(need)
	t.indexes.ensure_cap(need)
	t.type_chunk.ensure_cap(need)
	t.type_index.ensure_cap(need)
	t.group.ensure_cap(need)
	t.group_call.ensure_cap(need)
}

// grow gives the slots room for `count` keys, at least twice as many as they had.
fn (mut t NodeTable) grow(count int) {
	mut size := if t.slots.len == 0 { 1024 } else { 2 * t.slots.len }
	for size < 2 * count {
		size *= 2
	}
	mut slots := []u32{len: size}
	mask := u32(size - 1)
	for id, key in t.keys {
		mut h := node_table_hash(key, mask)
		for slots[h] != 0 {
			h = (h + 1) & mask
		}
		slots[h] = u32(id + 1)
	}
	t.slots = slots
}

@[inline]
fn (t &NodeTable) has(key u64, flag u8) bool {
	id := t.id(key)
	return id >= 0 && t.flags[id] & flag != 0
}

@[inline]
fn (t &NodeTable) attempted(key u64) bool {
	return t.has(key, node_attempted)
}

@[inline]
fn (t &NodeTable) typed(key u64) bool {
	return t.has(key, node_typed)
}

@[inline]
fn (t &NodeTable) has_handle(key u64) bool {
	return t.has(key, node_has_handle)
}

// handle is the handle of the tsgo node of a key, if it has one.
fn (t &NodeTable) handle(key u64) ?string {
	id := t.id(key)
	if id < 0 || t.flags[id] & node_has_handle == 0 {
		return none
	}
	return tsgo.node_handle_text(int(t.indexes[id]), t.kinds[id], t.path)
}

// ast_node is the tsgo node of a key, if it has one.
fn (t &NodeTable) ast_node(key u64) ?tsgo.AstNode {
	id := t.id(key)
	if id < 0 || t.flags[id] & node_has_handle == 0 {
		return none
	}
	return tsgo.AstNode{
		index: int(t.indexes[id])
		kind:  t.kinds[id]
	}
}

// handle_or_empty is handle, '' when there is none.
fn (t &NodeTable) handle_or_empty(key u64) string {
	return t.handle(key) or { '' }
}

// kind is the SyntaxKind of the tsgo node of a key, 0 when it has none.
fn (t &NodeTable) kind(key u64) u32 {
	id := t.id(key)
	return if id < 0 { u32(0) } else { t.kinds[id] }
}

// node_type is the type tsgo gave for a key, if it gave one.
fn (t &NodeTable) node_type(key u64) ?TypeResponse {
	id := t.id(key)
	if id < 0 || t.flags[id] & node_has_type == 0 {
		return none
	}
	return t.types[t.type_chunk[id]][t.type_index[id]]
}

fn (mut t NodeTable) set_flag(key u64, flag u8) {
	id := t.add(key)
	t.flags[id] |= flag
}

// set_node is the tsgo node found for a key: its index in the table of the file of `path` and its
// SyntaxKind.
fn (mut t NodeTable) set_node(key u64, index int, kind u32) {
	id := t.add(key)
	t.indexes[id] = u32(index)
	t.kinds[id] = kind
	t.flags[id] |= node_has_handle
}

// drop_node forgets the tsgo node of a key (its index and its kind).
fn (mut t NodeTable) drop_node(key u64) {
	id := t.id(key)
	if id < 0 {
		return
	}
	t.indexes[id] = 0
	t.kinds[id] = 0
	t.flags[id] &= ~node_has_handle
}

// add_types keeps an array of types answered by tsgo, and gives its place for set_type.
fn (mut t NodeTable) add_types(types []TypeResponse) u32 {
	t.types << types
	return u32(t.types.len - 1)
}

// set_type is the type of a key: types[index] of the array `chunk` (add_types).
fn (mut t NodeTable) set_type(key u64, chunk u32, index int) {
	id := t.add(key)
	t.type_chunk[id] = chunk
	t.type_index[id] = u32(index)
	t.flags[id] |= node_has_type
}
