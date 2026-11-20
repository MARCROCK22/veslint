module treesitter

fn C.ts_node_eq(self C.TSNode, other C.TSNode) bool

// NodeIndex holds the nodes of a tree by kind, in the order nodes_of_kind and nodes_of_kinds give
// them, so that asking for the nodes of a kind does not walk the tree again: the rules ask about a
// hundred times for each file. It is valid while the tree is.
pub struct NodeIndex {
mut:
	root      C.TSNode
	built     bool
	named     map[string]int // the bucket of each kind of named node
	anonymous map[string]int // the bucket of each kind of anonymous node with children
	buckets   []KindBucket
	count     int // nodes recorded
}

// KindBucket holds the nodes of a kind in preorder. `seq` is the place of each in the preorder of
// the tree, and `last` is the place of the last node of its subtree.
struct KindBucket {
mut:
	nodes []C.TSNode
	seq   []int
	last  []int
}

// new_node_index walks the tree under `root` once. It records the named nodes, which are the ones
// asked for, and the anonymous nodes with children, which can only be skipped; and makes this
// thread's flat tree (flat_tree.h), where node_parent, children and named_children find the nodes
// under `root`.
pub fn new_node_index(root C.TSNode) NodeIndex {
	ix, _ := index_tree(root, false)
	return ix
}

// new_node_index_and_token_ends gives what new_node_index and token_ends give, from one walk of
// the tree.
pub fn new_node_index_and_token_ends(root C.TSNode) (NodeIndex, TokenEnds) {
	ix, ends := index_tree(root, true)
	return ix, TokenEnds{
		ends: ends
	}
}

// What index_tree knows of a symbol of the grammar for the token ends, by its number (0: not
// asked yet).
const symbol_known = u8(1)
const symbol_jsx = u8(2) // its kind starts with `jsx_`
const symbol_jsx_element = u8(4)
const symbol_hash_bang = u8(8)

// symbol_flags is what token_ends looks at in the kind of a node.
fn symbol_flags(node C.TSNode, symbol int, mut flags_of [symbol_states]u8) u8 {
	mut flags := if symbol < symbol_states { flags_of[symbol] } else { u8(0) }
	if flags == 0 {
		kind := node_kind(node)
		flags = symbol_known
		if kind.starts_with('jsx_') {
			flags |= symbol_jsx
		}
		if kind == 'jsx_element' {
			flags |= symbol_jsx_element
		}
		if kind == 'hash_bang_line' {
			flags |= symbol_hash_bang
		}
		if symbol < symbol_states {
			flags_of[symbol] = flags
		}
	}
	return flags
}

// index_tree is new_node_index and, with `with_ends`, the ends token_ends gives: the same
// preorder walk, where token_ends neither enters an extra node (a comment) nor counts it. It walks
// the tree once into this thread's flat tree (flat_tree.h) and reads that. The place of a node in
// the flat tree is its `seq` in the buckets, and the place of the last node of its subtree its
// `last`.
fn index_tree(root C.TSNode, with_ends bool) (NodeIndex, []int) {
	mut ix := NodeIndex{
		root:  root
		built: true
	}
	mut ends := []int{}
	if !C.vt_flat_build(root) {
		panic('veslint: no flat tree for a file (out of memory, or its nodes out of order)')
	}
	count := int(C.vt_flat_count())
	flat := C.vt_flat_nodes()
	// The bucket of each symbol of the grammar plus one, as a named and as an anonymous node (0:
	// not asked yet), and its symbol_flags.
	mut named_of := [symbol_states]int{}
	mut anonymous_of := [symbol_states]int{}
	mut flags_of := [symbol_states]u8{}
	// The last node of the extra node (a comment) the walk is in, if it is in one: token_ends
	// does not enter those.
	mut extra_until := -1
	for i in 0 .. count {
		entry := unsafe { &flat[i] }
		node := entry.node
		is_named := entry.flags & flat_named != 0
		has_children := int(entry.last) > i
		symbol := int(entry.symbol)
		if is_named || has_children {
			known := if symbol >= symbol_states {
				0
			} else if is_named {
				named_of[symbol]
			} else {
				anonymous_of[symbol]
			}
			mut bucket := 0
			if known != 0 {
				bucket = known - 1
			} else {
				bucket = ix.bucket_of(node_kind(node), is_named)
				if symbol < symbol_states {
					if is_named {
						named_of[symbol] = bucket + 1
					} else {
						anonymous_of[symbol] = bucket + 1
					}
				}
			}
			ix.buckets[bucket].nodes << node
			ix.buckets[bucket].seq << i
			ix.buckets[bucket].last << int(entry.last)
			ix.count++
		}
		// What token_ends does with the node, outside extra nodes.
		if !with_ends || i <= extra_until {
			continue
		}
		if entry.flags & flat_extra != 0 {
			extra_until = int(entry.last)
			continue
		}
		flags := symbol_flags(node, symbol, mut flags_of)
		// The children of a JSX element have no leading trivia for TypeScript: the white space
		// between them is JsxText, also the one with line breaks, which tree-sitter skips. So the
		// start of each child counts as the end of a token.
		if flags & symbol_jsx != 0 && entry.parent != flat_none {
			parent := unsafe { &flat[entry.parent] }
			if symbol_flags(parent.node, int(parent.symbol), mut flags_of) & symbol_jsx_element != 0
				&& C.ts_node_start_byte(node) > C.ts_node_start_byte(parent.node) {
				ends << int(C.ts_node_start_byte(node))
			}
		}
		if !has_children {
			start := int(C.ts_node_start_byte(node))
			end := int(C.ts_node_end_byte(node))
			if end > start && flags & symbol_hash_bang == 0 {
				ends << end
			}
		}
	}
	return ix, ends
}

// bucket_of returns the bucket of a kind, which it makes if there is none yet.
fn (mut ix NodeIndex) bucket_of(kind string, is_named bool) int {
	if is_named {
		if bucket := ix.named[kind] {
			return bucket
		}
		ix.named[kind] = ix.buckets.len
	} else {
		if bucket := ix.anonymous[kind] {
			return bucket
		}
		ix.anonymous[kind] = ix.buckets.len
	}
	ix.buckets << KindBucket{}
	return ix.buckets.len - 1
}

// covers tells whether the index answers for `root`: it is the root it was built from.
fn (ix &NodeIndex) covers(root C.TSNode) bool {
	return ix.built && C.ts_node_eq(root, ix.root)
}

// of_kind gives what nodes_of_kind(root, kind) gives. It walks the tree when `root` is not the
// root of the index.
pub fn (ix &NodeIndex) of_kind(root C.TSNode, kind string) []C.TSNode {
	if !ix.covers(root) {
		return nodes_of_kind(root, &char(kind.str))
	}
	bucket := ix.named[kind] or { return []C.TSNode{} }
	return ix.buckets[bucket].nodes.clone()
}

// of_kinds gives what nodes_of_kinds(root, kinds, skip) gives. It walks the tree when `root` is
// not the root of the index.
pub fn (ix &NodeIndex) of_kinds(root C.TSNode, kinds []string, skip []string) []C.TSNode {
	if !ix.covers(root) {
		return nodes_of_kinds(root, kinds, skip)
	}
	mut wanted := []int{cap: kinds.len}
	for kind in kinds {
		bucket := ix.named[kind] or { continue }
		if bucket !in wanted {
			wanted << bucket
		}
	}
	mut skipped := []int{cap: 2 * skip.len}
	for kind in skip {
		if bucket := ix.named[kind] {
			if bucket !in skipped {
				skipped << bucket
			}
		}
		if bucket := ix.anonymous[kind] {
			if bucket !in skipped {
				skipped << bucket
			}
		}
	}
	if wanted.len == 1 && skipped.len == 0 {
		return ix.buckets[wanted[0]].nodes.clone()
	}
	// The subtrees that are not entered, in order: a skipped node inside another one adds nothing.
	mut skip_from := []int{}
	mut skip_to := []int{}
	mut heads := []int{len: skipped.len}
	mut covered := -1
	for {
		next := ix.next_bucket(skipped, heads)
		if next < 0 {
			break
		}
		at := heads[next]
		heads[next]++
		seq := ix.buckets[skipped[next]].seq[at]
		if seq > covered {
			covered = ix.buckets[skipped[next]].last[at]
			skip_from << seq
			skip_to << covered
		}
	}
	// The wanted nodes in preorder, except the ones inside a skipped subtree. A skipped node is
	// not inside its own subtree: the walk takes it before deciding not to enter.
	mut nodes := []C.TSNode{}
	heads = []int{len: wanted.len}
	mut interval := 0
	for {
		next := ix.next_bucket(wanted, heads)
		if next < 0 {
			break
		}
		at := heads[next]
		heads[next]++
		seq := ix.buckets[wanted[next]].seq[at]
		for interval < skip_from.len && skip_to[interval] < seq {
			interval++
		}
		if interval < skip_from.len && skip_from[interval] < seq {
			continue
		}
		nodes << ix.buckets[wanted[next]].nodes[at]
	}
	return nodes
}

// next_bucket picks, among `buckets`, the one whose next node (the one at its place in `heads`)
// comes first in the tree: its place in `buckets`, or -1 when all are used up.
fn (ix &NodeIndex) next_bucket(buckets []int, heads []int) int {
	mut best := -1
	mut best_seq := 0
	for i, bucket in buckets {
		if heads[i] >= ix.buckets[bucket].seq.len {
			continue
		}
		seq := ix.buckets[bucket].seq[heads[i]]
		if best < 0 || seq < best_seq {
			best = i
			best_seq = seq
		}
	}
	return best
}
