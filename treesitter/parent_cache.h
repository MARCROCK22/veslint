// The parent of each node of the tree being linted, recorded by the walk that builds its NodeIndex
// (node_index.v). tree-sitter's nodes do not know their parent: ts_node_parent descends from the
// root at every call, and the rules ask for parents all the time (it was a fifth of a lint of zod).
// One table per thread, since the lint workers each lint their own tree. A lookup for a node of
// another tree (a fragment of a .vue or .svelte file, a tree with no index) falls back to
// ts_node_parent; vt_parent_cache_clear forgets the tree before it is freed, so that a new tree at
// the same address never finds old parents.
#ifndef VESLINT_PARENT_CACHE_H
#define VESLINT_PARENT_CACHE_H

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "tree_sitter/api.h"

typedef struct {
	const void *id; // the node's id (the address of its subtree slot), NULL for an empty slot
	TSNode parent;
} vt_parent_slot;

static _Thread_local vt_parent_slot *vt_pc_slots = NULL;
static _Thread_local size_t vt_pc_capacity = 0; // a power of two
static _Thread_local size_t vt_pc_count = 0;
static _Thread_local const TSTree *vt_pc_tree = NULL;

static inline size_t vt_pc_hash(const void *id) {
	uint64_t x = (uint64_t)(uintptr_t)id;
	x ^= x >> 33;
	x *= 0xff51afd7ed558ccdULL;
	x ^= x >> 33;
	return (size_t)x;
}

static inline void vt_pc_insert(vt_parent_slot *slots, size_t capacity, const void *id, TSNode parent) {
	size_t i = vt_pc_hash(id) & (capacity - 1);
	while (slots[i].id != NULL && slots[i].id != id) {
		i = (i + 1) & (capacity - 1);
	}
	slots[i].id = id;
	slots[i].parent = parent;
}

// vt_parent_cache_begin starts the table of the tree of `root`, empty, sized for its nodes (at most
// half full): clearing a table left large by a previous file cost more than the walk of a small one.
static void vt_parent_cache_begin(TSNode root) {
	size_t capacity = (size_t)1 << 12;
	size_t nodes = ts_node_descendant_count(root);
	while (capacity < 2 * (nodes + 1)) {
		capacity <<= 1;
	}
	if (vt_pc_slots != NULL && vt_pc_capacity == capacity) {
		memset(vt_pc_slots, 0, vt_pc_capacity * sizeof(vt_parent_slot));
	} else {
		free(vt_pc_slots);
		vt_pc_slots = calloc(capacity, sizeof(vt_parent_slot));
		vt_pc_capacity = vt_pc_slots == NULL ? 0 : capacity;
	}
	vt_pc_count = 0;
	vt_pc_tree = vt_pc_slots == NULL ? NULL : root.tree;
}

// vt_parent_cache_put records the parent of a node of the table's tree.
static void vt_parent_cache_put(TSNode child, TSNode parent) {
	if (vt_pc_tree == NULL || child.tree != vt_pc_tree) {
		return;
	}
	if ((vt_pc_count + 1) * 2 > vt_pc_capacity) {
		size_t capacity = vt_pc_capacity * 2;
		vt_parent_slot *slots = calloc(capacity, sizeof(vt_parent_slot));
		if (slots == NULL) {
			// Out of memory: no table; every lookup falls back to ts_node_parent.
			vt_pc_tree = NULL;
			return;
		}
		for (size_t i = 0; i < vt_pc_capacity; i++) {
			if (vt_pc_slots[i].id != NULL) {
				vt_pc_insert(slots, capacity, vt_pc_slots[i].id, vt_pc_slots[i].parent);
			}
		}
		free(vt_pc_slots);
		vt_pc_slots = slots;
		vt_pc_capacity = capacity;
	}
	vt_pc_insert(vt_pc_slots, vt_pc_capacity, child.id, parent);
	vt_pc_count++;
}

// vt_parent_cache_clear forgets the tree (its nodes are about to be freed).
static void vt_parent_cache_clear(void) {
	vt_pc_tree = NULL;
}

// vt_node_parent is ts_node_parent, from the table when the node is of its tree.
static TSNode vt_node_parent(TSNode node) {
	if (vt_pc_tree != NULL && node.tree == vt_pc_tree && node.id != NULL) {
		size_t i = vt_pc_hash(node.id) & (vt_pc_capacity - 1);
		while (vt_pc_slots[i].id != NULL) {
			if (vt_pc_slots[i].id == node.id) {
				return vt_pc_slots[i].parent;
			}
			i = (i + 1) & (vt_pc_capacity - 1);
		}
	}
	return ts_node_parent(node);
}

#endif
