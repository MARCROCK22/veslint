// The tree being linted as a flat array, in preorder, made by one walk of a tree cursor (one per
// thread, since the lint workers each lint their own tree): every visible node with its parent, its
// next sibling, the last node of its subtree, its symbol, the field the cursor gives it and whether
// it is named or extra. The node index (node_index.v), the token ends, the source tokens and the
// ESTree converter read it instead of walking the tree again; the parents and the children the
// rules ask for come from it. tree-sitter's nodes do not know their parent (ts_node_parent descends
// from the root at every call) and ts_node_child starts from the first child at every call.
//
// A node is found by its start and its id (the address of its subtree slot, unique in a tree): in
// preorder the starts of the nodes never decrease, so the nodes that start at a byte are together,
// and the table has the first of them for each byte (vt_ft_first). That table is written in order
// by the walk; a hash table of the ids, written at random, was most of the time of the walk on a
// large file. A node of another tree (a fragment of a .vue or .svelte file, a tree with no index)
// is not there, and the functions fall back to tree-sitter's; vt_flat_clear forgets the tree before
// it is freed, so that a new tree at the same address never finds old nodes.
#ifndef VESLINT_FLAT_TREE_H
#define VESLINT_FLAT_TREE_H

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "tree_sitter/api.h"

#define VT_FLAT_NAMED 1
#define VT_FLAT_EXTRA 2
#define VT_FLAT_NONE UINT32_MAX

typedef struct {
	TSNode node;
	uint32_t parent; // VT_FLAT_NONE for the root
	uint32_t next; // the next sibling, VT_FLAT_NONE for the last child
	uint32_t last; // the last node of the subtree: the node itself for a leaf
	uint16_t symbol; // ts_node_symbol
	TSFieldId field; // ts_tree_cursor_current_field_id at the node
	uint8_t flags; // VT_FLAT_NAMED, VT_FLAT_EXTRA
} vt_flat_node;

static _Thread_local vt_flat_node *vt_ft_nodes = NULL;
static _Thread_local uint32_t vt_ft_count = 0;
static _Thread_local uint32_t vt_ft_capacity = 0;
// The first node that starts at each byte of the text, for the bytes where one starts (the others
// are left as they are: no node of the tree asks for them).
static _Thread_local uint32_t *vt_ft_first = NULL;
static _Thread_local size_t vt_ft_first_capacity = 0;
static _Thread_local const TSTree *vt_ft_tree = NULL; // NULL: no tree
// The walk's stacks: the open nodes and the last child seen of each.
static _Thread_local uint32_t *vt_ft_open = NULL;
static _Thread_local uint32_t *vt_ft_prev = NULL;
static _Thread_local uint32_t vt_ft_open_capacity = 0;
static _Thread_local TSTreeCursor vt_ft_cursor;
static _Thread_local bool vt_ft_cursor_ready = false;

// vt_flat_clear forgets the tree (its nodes are about to be freed).
static void vt_flat_clear(void) {
	vt_ft_tree = NULL;
	vt_ft_count = 0;
}

// vt_ft_fail drops the table when memory runs out: every lookup falls back to tree-sitter.
static bool vt_ft_fail(void) {
	vt_flat_clear();
	return false;
}

// vt_flat_build walks the tree under `root` (normally the root of its tree) into the table, and
// tells whether it could.
static bool vt_flat_build(TSNode root) {
	vt_flat_clear();
	uint32_t nodes = ts_node_descendant_count(root);
	if (nodes > vt_ft_capacity) {
		free(vt_ft_nodes);
		vt_ft_nodes = malloc((size_t)nodes * sizeof(vt_flat_node));
		vt_ft_capacity = vt_ft_nodes == NULL ? 0 : nodes;
		if (vt_ft_nodes == NULL) {
			return vt_ft_fail();
		}
	}
	size_t bytes = (size_t)ts_node_end_byte(root) + 1;
	if (bytes > vt_ft_first_capacity) {
		free(vt_ft_first);
		vt_ft_first = malloc(bytes * sizeof(uint32_t));
		vt_ft_first_capacity = vt_ft_first == NULL ? 0 : bytes;
		if (vt_ft_first == NULL) {
			return vt_ft_fail();
		}
	}
	// The start of the previous node: when a start comes before it (never seen), the table
	// cannot find the nodes and is dropped.
	uint32_t previous_start = 0;
	if (!vt_ft_cursor_ready) {
		vt_ft_cursor = ts_tree_cursor_new(root);
		vt_ft_cursor_ready = true;
	} else {
		ts_tree_cursor_reset(&vt_ft_cursor, root);
	}
	uint32_t depth = 0;
	uint32_t count = 0;
	for (;;) {
		if (count == vt_ft_capacity) {
			// More nodes than ts_node_descendant_count said: it does not happen, but the table
			// must not overflow.
			return vt_ft_fail();
		}
		TSNode node = ts_tree_cursor_current_node(&vt_ft_cursor);
		uint32_t index = count++;
		vt_flat_node *entry = &vt_ft_nodes[index];
		entry->node = node;
		entry->parent = depth == 0 ? VT_FLAT_NONE : vt_ft_open[depth - 1];
		entry->next = VT_FLAT_NONE;
		entry->last = index;
		entry->symbol = ts_node_symbol(node);
		entry->field = depth == 0 ? 0 : ts_tree_cursor_current_field_id(&vt_ft_cursor);
		entry->flags = (ts_node_is_named(node) ? VT_FLAT_NAMED : 0) | (ts_node_is_extra(node) ? VT_FLAT_EXTRA : 0);
		if (depth > 0) {
			if (vt_ft_prev[depth - 1] != VT_FLAT_NONE) {
				vt_ft_nodes[vt_ft_prev[depth - 1]].next = index;
			}
			vt_ft_prev[depth - 1] = index;
		}
		uint32_t start = ts_node_start_byte(node);
		if (start < previous_start || start >= vt_ft_first_capacity) {
			return vt_ft_fail();
		}
		if (index == 0 || start != previous_start) {
			vt_ft_first[start] = index;
		}
		previous_start = start;
		if (ts_tree_cursor_goto_first_child(&vt_ft_cursor)) {
			if (depth == vt_ft_open_capacity) {
				uint32_t capacity = vt_ft_open_capacity == 0 ? 256 : vt_ft_open_capacity * 2;
				uint32_t *open = realloc(vt_ft_open, capacity * sizeof(uint32_t));
				if (open == NULL) {
					return vt_ft_fail();
				}
				vt_ft_open = open;
				uint32_t *prev = realloc(vt_ft_prev, capacity * sizeof(uint32_t));
				if (prev == NULL) {
					return vt_ft_fail();
				}
				vt_ft_prev = prev;
				vt_ft_open_capacity = capacity;
			}
			vt_ft_open[depth] = index;
			vt_ft_prev[depth] = VT_FLAT_NONE;
			depth++;
			continue;
		}
		while (!ts_tree_cursor_goto_next_sibling(&vt_ft_cursor)) {
			if (depth == 0 || !ts_tree_cursor_goto_parent(&vt_ft_cursor)) {
				vt_ft_count = count;
				vt_ft_tree = root.tree;
				return true;
			}
			depth--;
			vt_ft_nodes[vt_ft_open[depth]].last = count - 1;
		}
	}
}

// vt_flat_find gives the index of a node in the table, or -1 when it is not there: among the
// nodes that start where it starts, the one with its id.
static inline int64_t vt_flat_find(TSNode node) {
	if (vt_ft_tree == NULL || node.tree != vt_ft_tree || node.id == NULL) {
		return -1;
	}
	uint32_t start = ts_node_start_byte(node);
	if (start >= vt_ft_first_capacity) {
		return -1;
	}
	uint32_t i = vt_ft_first[start];
	// The node at `i` may be of an earlier tree when no node of this one starts there (a node
	// of this tree that is not in the table, under another root).
	for (; i < vt_ft_count && ts_node_start_byte(vt_ft_nodes[i].node) == start; i++) {
		if (vt_ft_nodes[i].node.id == node.id) {
			return i;
		}
	}
	return -1;
}

static inline vt_flat_node *vt_flat_nodes(void) {
	return vt_ft_nodes;
}

static inline uint32_t vt_flat_count(void) {
	return vt_ft_tree == NULL ? 0 : vt_ft_count;
}

// vt_node_parent is ts_node_parent, from the table when the node is of its tree.
static TSNode vt_node_parent(TSNode node) {
	int64_t index = vt_flat_find(node);
	if (index >= 0) {
		uint32_t parent = vt_ft_nodes[index].parent;
		if (parent == VT_FLAT_NONE) {
			// The root of the table: its parent, if it has one, is outside.
			return ts_node_parent(node);
		}
		return vt_ft_nodes[parent].node;
	}
	return ts_node_parent(node);
}

static _Thread_local TSTreeCursor vt_ch_cursor;
static _Thread_local bool vt_ch_ready = false;

// vt_children writes to `out` (room for `capacity` nodes) what ts_node_child(self, i) gives for
// each i below ts_node_child_count(self) or, with `named`, ts_node_named_child(self, i) below
// ts_node_named_child_count(self); and returns how many it wrote. It returns -1 for the named
// children when a visible anonymous child has named children: ts_node_named_child counts and
// descends into those differently from a walk, so the caller asks it. The children are the ones of
// the table, or of a walk of a tree cursor (one per thread, reused) for a node of another tree.
static int vt_children(TSNode self, bool named, TSNode *out, uint32_t capacity) {
	uint32_t count = 0;
	int64_t index = vt_flat_find(self);
	if (index >= 0) {
		if (vt_ft_nodes[index].last == (uint32_t)index) {
			return 0;
		}
		for (uint32_t child = (uint32_t)index + 1; child != VT_FLAT_NONE; child = vt_ft_nodes[child].next) {
			if (named && !(vt_ft_nodes[child].flags & VT_FLAT_NAMED)) {
				if (ts_node_named_child_count(vt_ft_nodes[child].node) > 0) {
					return -1;
				}
				continue;
			}
			if (count == capacity) {
				return -1;
			}
			out[count++] = vt_ft_nodes[child].node;
		}
		return (int)count;
	}
	if (!vt_ch_ready) {
		vt_ch_cursor = ts_tree_cursor_new(self);
		vt_ch_ready = true;
	} else {
		ts_tree_cursor_reset(&vt_ch_cursor, self);
	}
	if (!ts_tree_cursor_goto_first_child(&vt_ch_cursor)) {
		return 0;
	}
	do {
		TSNode child = ts_tree_cursor_current_node(&vt_ch_cursor);
		if (named && !ts_node_is_named(child)) {
			if (ts_node_named_child_count(child) > 0) {
				return -1;
			}
			continue;
		}
		if (count == capacity) {
			return -1;
		}
		out[count++] = child;
	} while (ts_tree_cursor_goto_next_sibling(&vt_ch_cursor));
	return (int)count;
}

#endif
