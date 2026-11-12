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
// asked for, and the anonymous nodes with children, which can only be skipped.
pub fn new_node_index(root C.TSNode) NodeIndex {
	mut ix := NodeIndex{
		root:  root
		built: true
	}
	mut cursor := C.ts_tree_cursor_new(root)
	defer {
		C.ts_tree_cursor_delete(&cursor)
	}
	// The bucket of each symbol of the grammar plus one, as a named and as an anonymous node (0:
	// not asked yet).
	mut named_of := [symbol_states]int{}
	mut anonymous_of := [symbol_states]int{}
	// The nodes whose children are being visited: the bucket of each (-1 if it is not recorded)
	// and its place in it.
	mut open_buckets := []int{}
	mut open_places := []int{}
	for {
		node := C.ts_tree_cursor_current_node(&cursor)
		is_named := C.ts_node_is_named(node)
		mut bucket := -1
		mut place := 0
		if is_named || C.ts_node_child_count(node) > 0 {
			symbol := int(C.ts_node_symbol(node))
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
		if C.ts_tree_cursor_goto_first_child(&cursor) {
			open_buckets << bucket
			open_places << place
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
				return ix
			}
			open := open_buckets.pop()
			open_place := open_places.pop()
			if open >= 0 {
				ix.buckets[open].last[open_place] = ix.count - 1
			}
		}
	}
	return ix
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
