// The rows (rows.h) of a tree-sitter tree: one walk of a tree cursor, after which the tree can be
// freed. This and incremental.h are the only code that reads tree-sitter's trees.
//
// VESLINT_ROWS_CHECK=1 (treesitter.v) also compares, for every node, what each function of rows.h
// answers with what tree-sitter's ts_node_* function answers (vt_rows_check), and writes the
// differences to stderr.
#ifndef VESLINT_ROWS_BUILD_H
#define VESLINT_ROWS_BUILD_H

#include <stdio.h>
#include "tree_sitter/api.h"
#include "rows.h"

// The walk's stacks: the open rows of the cursor. One per thread, since the lint workers each
// parse their own files.
static _Thread_local uint32_t *vt_rb_open = NULL;
static _Thread_local uint32_t vt_rb_open_capacity = 0;
static _Thread_local TSTreeCursor vt_rb_cursor;
static _Thread_local bool vt_rb_cursor_ready = false;

// The kind of a node: the name of its symbol in the language tables.
static inline const char *vt_node_type(vt_node n) {
	return ts_language_symbol_name((const TSLanguage *)n.rows->language, vt_node_row(n)->symbol);
}

static inline TSLanguage *vt_node_language(vt_node n) {
	return (TSLanguage *)n.rows->language;
}

static inline TSLanguage *vt_rows_language(const vt_rows *rows) {
	return (TSLanguage *)rows->language;
}

static inline uint8_t vt_rb_flags(TSNode node) {
	return (ts_node_is_named(node) ? VT_ROW_NAMED : 0) | (ts_node_is_extra(node) ? VT_ROW_EXTRA : 0)
		| (ts_node_is_missing(node) ? VT_ROW_MISSING : 0) | (ts_node_is_error(node) ? VT_ROW_ERROR : 0)
		| (ts_node_has_error(node) ? VT_ROW_HAS_ERROR : 0);
}

// vt_rows_from_tree gives the rows of `tree`, NULL when memory runs out.
static vt_rows *vt_rows_from_tree(const TSTree *tree) {
	TSNode root = ts_tree_root_node(tree);
	uint32_t nodes = ts_node_descendant_count(root);
	vt_rows *rows = vt_rows_new(ts_tree_language(tree), nodes);
	if (rows == NULL) {
		return NULL;
	}
	if (!vt_rb_cursor_ready) {
		vt_rb_cursor = ts_tree_cursor_new(root);
		vt_rb_cursor_ready = true;
	} else {
		ts_tree_cursor_reset(&vt_rb_cursor, root);
	}
	uint32_t depth = 0;
	for (;;) {
		if (rows->count == rows->capacity) {
			// More nodes than ts_node_descendant_count said: it does not happen, but the rows
			// must not overflow.
			uint32_t capacity = rows->capacity * 2 + 16;
			vt_row *more = (vt_row *)realloc(rows->rows, (size_t)capacity * sizeof(vt_row));
			if (more == NULL) {
				vt_rows_free(rows);
				return NULL;
			}
			rows->rows = more;
			rows->capacity = capacity;
		}
		TSNode node = ts_tree_cursor_current_node(&vt_rb_cursor);
		uint32_t index = rows->count++;
		vt_row *row = &rows->rows[index];
		TSPoint start = ts_node_start_point(node);
		TSPoint end = ts_node_end_point(node);
		row->start_byte = ts_node_start_byte(node);
		row->end_byte = ts_node_end_byte(node);
		row->start_row = start.row;
		row->start_column = start.column;
		row->end_row = end.row;
		row->end_column = end.column;
		row->parent = depth == 0 ? VT_ROW_NONE : vt_rb_open[depth - 1];
		row->symbol = ts_node_symbol(node);
		row->field = depth == 0 ? 0 : ts_tree_cursor_current_field_id(&vt_rb_cursor);
		row->flags = vt_rb_flags(node);
		if (ts_tree_cursor_goto_first_child(&vt_rb_cursor)) {
			if (depth == vt_rb_open_capacity) {
				uint32_t capacity = vt_rb_open_capacity == 0 ? 256 : vt_rb_open_capacity * 2;
				uint32_t *open = (uint32_t *)realloc(vt_rb_open, capacity * sizeof(uint32_t));
				if (open == NULL) {
					vt_rows_free(rows);
					return NULL;
				}
				vt_rb_open = open;
				vt_rb_open_capacity = capacity;
			}
			vt_rb_open[depth++] = index;
			continue;
		}
		while (!ts_tree_cursor_goto_next_sibling(&vt_rb_cursor)) {
			if (depth == 0 || !ts_tree_cursor_goto_parent(&vt_rb_cursor)) {
				if (!vt_rows_link(rows)) {
					vt_rows_free(rows);
					return NULL;
				}
				return rows;
			}
			depth--;
		}
	}
}

// The check (VESLINT_ROWS_CHECK=1): the row of each tree-sitter node, found by its id (the
// address of its subtree slot, unique in a tree) in an open-addressing table.
typedef struct {
	const void *id;
	uint32_t index;
} vt_rc_slot;

static uint32_t vt_rc_index(const vt_rc_slot *slots, uint32_t mask, TSNode node) {
	if (ts_node_is_null(node)) {
		return VT_ROW_NONE;
	}
	uint64_t h = (uint64_t)(uintptr_t)node.id * 0x9E3779B97F4A7C15ULL;
	for (uint32_t i = (uint32_t)(h >> 32) & mask;; i = (i + 1) & mask) {
		if (slots[i].id == node.id) {
			return slots[i].index;
		}
		if (slots[i].id == NULL) {
			return VT_ROW_NONE - 1; // a node that is not a row
		}
	}
}

static uint32_t vt_rc_row(vt_node n) {
	return vt_node_is_null(n) ? VT_ROW_NONE : n.index;
}

static _Thread_local uint64_t vt_rc_differences = 0;
static _Thread_local uint64_t vt_rc_quirks = 0;

// vt_rc_out is where the check writes: VESLINT_ROWS_CHECK_LOG (appended to), else stderr.
static FILE *vt_rc_out(void) {
	static FILE *out = NULL;
	if (out == NULL) {
		const char *path = getenv("VESLINT_ROWS_CHECK_LOG");
		out = path != NULL ? fopen(path, "a") : NULL;
		if (out == NULL) {
			out = stderr;
		} else {
			setvbuf(out, NULL, _IOLBF, 0);
		}
	}
	return out;
}

// vt_rc_report writes a difference (the first ones of each tree); a quirk of tree-sitter is
// counted apart, and written only with VESLINT_ROWS_CHECK_QUIRKS.
static void vt_rc_report(const vt_rows *rows, uint32_t index, const char *what, uint64_t ts, uint64_t row, bool quirk) {
	if (quirk) {
		vt_rc_quirks++;
		if (getenv("VESLINT_ROWS_CHECK_QUIRKS") == NULL) {
			return;
		}
	} else {
		vt_rc_differences++;
	}
	if (vt_rc_differences + vt_rc_quirks <= 20) {
		const vt_row *r = &rows->rows[index];
		const TSLanguage *language = (const TSLanguage *)rows->language;
		fprintf(vt_rc_out(), "veslint: rows check: %snode %u (%s, bytes %u-%u): %s: tree-sitter %llu (%s), rows %llu (%s)\n",
			quirk ? "quirk: " : "", index, ts_language_symbol_name(language, r->symbol), r->start_byte,
			r->end_byte, what, (unsigned long long)ts,
			ts < rows->count ? ts_language_symbol_name(language, rows->rows[ts].symbol) : "-",
			(unsigned long long)row,
			row < rows->count ? ts_language_symbol_name(language, rows->rows[row].symbol) : "-");
	}
}

// vt_rows_check compares the rows with the tree they were built from and gives the number of
// differences (the first ones are written to stderr).
static uint64_t vt_rows_check(const vt_rows *rows, const TSTree *tree) {
	vt_rc_differences = 0;
	vt_rc_quirks = 0;
	uint32_t size = 16;
	while (size < rows->count * 2) {
		size *= 2;
	}
	vt_rc_slot *slots = (vt_rc_slot *)calloc(size, sizeof(vt_rc_slot));
	TSNode *nodes = (TSNode *)malloc((size_t)(rows->count + 1) * sizeof(TSNode));
	if (slots == NULL || nodes == NULL) {
		free(slots);
		free(nodes);
		fprintf(stderr, "veslint: rows check: out of memory\n");
		return 1;
	}
	uint32_t mask = size - 1;
	TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node(tree));
	uint32_t count = 0;
	for (;;) {
		TSNode node = ts_tree_cursor_current_node(&cursor);
		if (count < rows->count) {
			nodes[count] = node;
			uint64_t h = (uint64_t)(uintptr_t)node.id * 0x9E3779B97F4A7C15ULL;
			uint32_t i = (uint32_t)(h >> 32) & mask;
			while (slots[i].id != NULL) {
				i = (i + 1) & mask;
			}
			slots[i].id = node.id;
			slots[i].index = count;
		}
		count++;
		if (ts_tree_cursor_goto_first_child(&cursor)) {
			continue;
		}
		bool done = false;
		while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
			if (!ts_tree_cursor_goto_parent(&cursor)) {
				done = true;
				break;
			}
		}
		if (done) {
			break;
		}
	}
	ts_tree_cursor_delete(&cursor);
	if (count != rows->count) {
		vt_rc_report(rows, 0, "nodes", count, rows->count, false);
		count = count < rows->count ? count : rows->count;
	}
	const TSLanguage *language = (const TSLanguage *)rows->language;
	uint32_t fields = ts_language_field_count(language);
	for (uint32_t index = 0; index < count; index++) {
		TSNode t = nodes[index];
		vt_node n = vt_node_at(rows, index);
		const vt_row *r = &rows->rows[index];
		TSPoint start = ts_node_start_point(t);
		TSPoint end = ts_node_end_point(t);
#define VT_RC(what, a, b, quirk) \
	do { \
		uint64_t va = (uint64_t)(a), vb = (uint64_t)(b); \
		if (va != vb) { \
			vt_rc_report(rows, index, what, va, vb, quirk); \
		} \
	} while (0)
		VT_RC("symbol", ts_node_symbol(t), r->symbol, false);
		VT_RC("kind", strcmp(ts_node_type(t), ts_language_symbol_name(language, r->symbol)), 0, false);
		VT_RC("flags", vt_rb_flags(t), r->flags, false);
		VT_RC("start", ts_node_start_byte(t), r->start_byte, false);
		VT_RC("end", ts_node_end_byte(t), r->end_byte, false);
		VT_RC("start row", start.row, r->start_row, false);
		VT_RC("start column", start.column, r->start_column, false);
		VT_RC("end row", end.row, r->end_row, false);
		VT_RC("end column", end.column, r->end_column, false);
		VT_RC("parent", vt_rc_index(slots, mask, ts_node_parent(t)), vt_rc_row(vt_node_parent(n)), false);
		VT_RC("next sibling", vt_rc_index(slots, mask, ts_node_next_sibling(t)),
			vt_rc_row(vt_node_next_sibling(n)), false);
		VT_RC("prev sibling", vt_rc_index(slots, mask, ts_node_prev_sibling(t)),
			vt_rc_row(vt_node_prev_sibling(n)), false);
		VT_RC("next named sibling", vt_rc_index(slots, mask, ts_node_next_named_sibling(t)),
			vt_rc_row(vt_node_next_named_sibling(n)), false);
		VT_RC("prev named sibling", vt_rc_index(slots, mask, ts_node_prev_named_sibling(t)),
			vt_rc_row(vt_node_prev_named_sibling(n)), false);
		uint32_t children = ts_node_child_count(t);
		VT_RC("child count", children, vt_node_child_count(n), false);
		// ts_node_child walks from the first child at every call: the children of a node with
		// many are compared with a walk of a cursor.
		if (children > 0) {
			TSTreeCursor walk = ts_tree_cursor_new(t);
			ts_tree_cursor_goto_first_child(&walk);
			vt_node rc = vt_node_first_child(n);
			for (uint32_t i = 0; i < children; i++) {
				if (i > 0) {
					ts_tree_cursor_goto_next_sibling(&walk);
					rc = vt_node_next(rc);
				}
				TSNode tc = ts_tree_cursor_current_node(&walk);
				VT_RC("child", vt_rc_index(slots, mask, tc), vt_rc_row(rc), false);
				if (children <= 64) {
					VT_RC("child at", vt_rc_index(slots, mask, ts_node_child(t, i)),
						vt_rc_row(vt_node_child(n, i)), false);
				}
			}
			ts_tree_cursor_delete(&walk);
		}
		uint32_t named = ts_node_named_child_count(t);
		VT_RC("named child count", named, vt_node_named_child_count(n), false);
		for (uint32_t i = 0; i < named && i < 64; i++) {
			VT_RC("named child", vt_rc_index(slots, mask, ts_node_named_child(t, i)),
				vt_rc_row(vt_node_named_child(n, i)), false);
		}
		for (uint32_t f = 1; f <= fields; f++) {
			uint32_t ta = vt_rc_index(slots, mask, ts_node_child_by_field_id(t, (TSFieldId)f));
			uint32_t ra = vt_rc_row(vt_node_child_by_field_id(n, (uint16_t)f));
			// tree-sitter's quirks: a field it inherits through a rule that an alias made visible
			// gives a grandchild, and an ERROR node gives no fields.
			bool quirk = (ta < count && rows->rows[ta].parent != index)
				|| ((r->flags & VT_ROW_ERROR) != 0 && ta == VT_ROW_NONE);
			VT_RC("field", ta, ra, quirk);
		}
#undef VT_RC
	}
	free(slots);
	free(nodes);
	return vt_rc_differences;
}

#endif
