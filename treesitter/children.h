// The children of a node in one pass of a tree cursor (one per thread, reused). ts_node_child and
// ts_node_named_child walk the children from the first one at every call, so asking for each child
// in turn is quadratic in their number (a block of a thousand statements, a large object literal).
#ifndef VESLINT_CHILDREN_H
#define VESLINT_CHILDREN_H

#include <stdbool.h>
#include <stdint.h>
#include "tree_sitter/api.h"

static _Thread_local TSTreeCursor vt_ch_cursor;
static _Thread_local bool vt_ch_ready = false;

// vt_children writes to `out` (room for `capacity` nodes) what ts_node_child(self, i) gives for
// each i below ts_node_child_count(self) or, with `named`, ts_node_named_child(self, i) below
// ts_node_named_child_count(self); and returns how many it wrote. It returns -1 for the named
// children when a visible anonymous child has named children: ts_node_named_child counts and
// descends into those differently from a walk, so the caller asks it.
static int vt_children(TSNode self, bool named, TSNode *out, uint32_t capacity) {
	if (!vt_ch_ready) {
		vt_ch_cursor = ts_tree_cursor_new(self);
		vt_ch_ready = true;
	} else {
		ts_tree_cursor_reset(&vt_ch_cursor, self);
	}
	uint32_t count = 0;
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
