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

// KindBucket holds the nodes of a kind in preorder. `seq` is the place of each among the recorded
// nodes of the tree, in preorder, and `last` is the place of the last one in its subtree.
struct KindBucket {
mut:
	nodes []C.TSNode
	seq   []int
	last  []int
}

// new_node_index walks the tree under `root` once. It records the named nodes, which are the ones
// asked for, and the anonymous nodes with children, which can only be skipped; and, for
// node_parent, the parent of every node under `root` (parent_cache.h, this thread's).
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
// preorder walk, where token_ends neither enters an extra node (a comment) nor counts it.
fn index_tree(root C.TSNode, with_ends bool) (NodeIndex, []int) {
	mut ix := NodeIndex{
		root:  root
		built: true
	}
	mut ends := []int{}
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	// The bucket of each symbol of the grammar plus one, as a named and as an anonymous node (0:
	// not asked yet), and its symbol_flags.
	mut named_of := [symbol_states]int{}
	mut anonymous_of := [symbol_states]int{}
	mut flags_of := [symbol_states]u8{}
	// The nodes whose children are being visited: the bucket of each (-1 if it is not recorded)
	// and its place in it.
	mut open_buckets := []int{}
	mut open_places := []int{}
	// The nodes whose children are being visited, the root first, and whether each is an extra
	// node or in one (token_ends does not walk its children).
	mut open_nodes := []C.TSNode{}
	mut open_extra := []bool{}
	C.vt_parent_cache_begin(root)
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		has_parent := open_nodes.len > 0
		if has_parent {
			C.vt_parent_cache_put(node, open_nodes.last())
		}
		is_named := C.ts_node_is_named(node)
		child_count := C.ts_node_child_count(node)
		symbol := int(C.ts_node_symbol(node))
		mut bucket := -1
		mut place := 0
		if is_named || child_count > 0 {
			known := if symbol >= symbol_states {
				0
			} else if is_named {
				named_of[symbol]
			} else {
				anonymous_of[symbol]
			}
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
			place = ix.buckets[bucket].nodes.len
			ix.buckets[bucket].nodes << node
			ix.buckets[bucket].seq << ix.count
			ix.buckets[bucket].last << ix.count
			ix.count++
		}
		// What token_ends does with the node, outside extra nodes.
		in_extra := has_parent && open_extra.last()
		mut extra := false
		if with_ends && !in_extra {
			extra = C.ts_node_is_extra(node)
			if !extra {
				flags := symbol_flags(node, symbol, mut flags_of)
				// The children of a JSX element have no leading trivia for TypeScript: the
				// white space between them is JsxText, also the one with line breaks, which
				// tree-sitter skips. So the start of each child counts as the end of a token.
				if flags & symbol_jsx != 0 && has_parent {
					parent := open_nodes.last()
					if symbol_flags(parent, int(C.ts_node_symbol(parent)), mut flags_of) & symbol_jsx_element != 0
						&& C.ts_node_start_byte(node) > C.ts_node_start_byte(parent) {
						ends << int(C.ts_node_start_byte(node))
					}
				}
				if child_count == 0 {
					start := int(C.ts_node_start_byte(node))
					end := int(C.ts_node_end_byte(node))
					if end > start && flags & symbol_hash_bang == 0 {
						ends << end
					}
				}
			}
		}
		if C.ts_tree_cursor_goto_first_child(&cursor) {
			open_buckets << bucket
			open_places << place
			open_nodes << node
			open_extra << (in_extra || extra)
			continue
		}
		for !C.ts_tree_cursor_goto_next_sibling(&cursor) {
			if !C.ts_tree_cursor_goto_parent(&cursor) {
				// Only the root is left open.
				for i, open in open_buckets {
					if open >= 0 {
						ix.buckets[open].last[open_places[i]] = ix.count - 1
					}
				}
				return ix, ends
			}
			open := open_buckets.pop()
			open_place := open_places.pop()
			open_nodes.delete_last()
			open_extra.delete_last()
			if open >= 0 {
				ix.buckets[open].last[open_place] = ix.count - 1
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
