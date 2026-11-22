// The rows of a parsed file: every visible node of its tree in preorder, each with all veslint asks
// of a node (kind, field, flags, range, shape). veslint reads a tree only through them: a parser
// fills them once per file (rows_build.h does it from tree-sitter's tree, which is freed right
// after) and the rules, the ESTree converter, the scope analysis and the tokens read them. This
// header does not need tree-sitter, so another parser (a converter from TypeScript's AST) can fill
// the rows from C or Go.
//
// Filling the rows (one call per file, one buffer):
//
//   vt_rows *rows = vt_rows_new(language, count); // room for `count` rows, NULL without memory
//   for each node, in preorder (a node before its children, the children in order):
//       vt_row *row = &rows->rows[rows->count++];
//       row->symbol, row->field, row->flags, the range and row->parent (VT_ROW_NONE for the root)
//   vt_rows_link(rows); // next, prev and last, from the parents
//   ... read them through vt_node (below) ...
//   vt_rows_free(rows);
//
// The values (they are tree-sitter's, since the rules were written for its tree):
//   symbol    the node's symbol in the language tables of the linked grammar (ts_node_symbol: an
//             alias's symbol for an aliased node; 65535 for ERROR); its name is the node's kind
//   field     the field id the node has under its parent (ts_tree_cursor_current_field_id: also
//             the field of a hidden node the node is the visible part of), 0 for none
//   flags     VT_ROW_NAMED (a named node or a named alias), VT_ROW_EXTRA (a comment),
//             VT_ROW_MISSING (a zero-width node the parser inserted), VT_ROW_ERROR (an ERROR node),
//             VT_ROW_HAS_ERROR (an ERROR or MISSING node in the subtree, the node included)
//   range     start and end in bytes of the text, and as (row, column in bytes) where a row ends
//             at each `\n`
//   parent    the row of the nearest visible ancestor
//   next, prev, last  (vt_rows_link) the next and the previous sibling under the same parent,
//             VT_ROW_NONE for none, and the last row of the subtree (the row itself for a leaf)
//
// A node is a row of a set of rows: vt_node {rows, index}, 16 bytes passed by value. The functions
// below answer what tree-sitter's ts_node_* functions answer, with tree-sitter's own quirks where
// the rules saw them (vt_node_named_child).
#ifndef VESLINT_ROWS_H
#define VESLINT_ROWS_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define VT_ROW_NONE UINT32_MAX
#define VT_ROW_NAMED 1
#define VT_ROW_EXTRA 2
#define VT_ROW_MISSING 4
#define VT_ROW_ERROR 8
#define VT_ROW_HAS_ERROR 16

typedef struct {
	uint32_t start_byte;
	uint32_t end_byte;
	uint32_t start_row;
	uint32_t start_column;
	uint32_t end_row;
	uint32_t end_column;
	uint32_t parent;
	uint32_t next;
	uint32_t prev;
	uint32_t last;
	uint16_t symbol;
	uint16_t field;
	uint8_t flags;
} vt_row;

typedef struct {
	vt_row *rows;
	uint32_t count;
	uint32_t capacity;
	// The language tables the symbols and the fields are numbers of (a `const TSLanguage *`):
	// the kind and field names come from them.
	const void *language;
} vt_rows;

typedef struct {
	const vt_rows *rows; // NULL for the null node
	uint32_t index;
} vt_node;

typedef struct {
	uint32_t row;
	uint32_t column;
} vt_point;

// vt_rows_new makes empty rows with room for `capacity` of them, NULL when memory runs out.
static vt_rows *vt_rows_new(const void *language, uint32_t capacity) {
	vt_rows *rows = (vt_rows *)malloc(sizeof(vt_rows));
	if (rows == NULL) {
		return NULL;
	}
	rows->rows = (vt_row *)malloc((size_t)(capacity == 0 ? 1 : capacity) * sizeof(vt_row));
	if (rows->rows == NULL) {
		free(rows);
		return NULL;
	}
	rows->count = 0;
	rows->capacity = capacity;
	rows->language = language;
	return rows;
}

static void vt_rows_free(vt_rows *rows) {
	if (rows != NULL) {
		free(rows->rows);
		free(rows);
	}
}

// vt_rows_link sets next, prev and last from the parents of rows in preorder. The rows of a
// subtree follow their root, so the subtree of a row ends where a row whose parent is outside it
// begins: the open rows are a stack, and each row closes the open rows that are not its parent.
static bool vt_rows_link(vt_rows *rows) {
	uint32_t count = rows->count;
	uint32_t *open = (uint32_t *)malloc((size_t)(count == 0 ? 1 : count) * sizeof(uint32_t));
	uint32_t *child = (uint32_t *)malloc((size_t)(count == 0 ? 1 : count) * sizeof(uint32_t));
	if (open == NULL || child == NULL) {
		free(open);
		free(child);
		return false;
	}
	uint32_t depth = 0;
	for (uint32_t i = 0; i < count; i++) {
		vt_row *row = &rows->rows[i];
		while (depth > 0 && open[depth - 1] != row->parent) {
			rows->rows[open[depth - 1]].last = i - 1;
			depth--;
		}
		row->next = VT_ROW_NONE;
		row->prev = VT_ROW_NONE;
		row->last = i;
		if (depth > 0) {
			uint32_t previous = child[depth - 1];
			if (previous != VT_ROW_NONE) {
				rows->rows[previous].next = i;
				row->prev = previous;
			}
			child[depth - 1] = i;
		}
		open[depth] = i;
		child[depth] = VT_ROW_NONE;
		depth++;
	}
	while (depth > 0) {
		rows->rows[open[depth - 1]].last = count - 1;
		depth--;
	}
	free(open);
	free(child);
	return true;
}

static inline vt_node vt_node_null(void) {
	vt_node none = {NULL, 0};
	return none;
}

static inline vt_node vt_node_at(const vt_rows *rows, uint32_t index) {
	vt_node node = {rows, index};
	return node;
}

static inline vt_node vt_rows_root(const vt_rows *rows) {
	return rows == NULL || rows->count == 0 ? vt_node_null() : vt_node_at(rows, 0);
}

static inline vt_rows *vt_node_rows(vt_node n) {
	return (vt_rows *)n.rows;
}

static inline const vt_row *vt_node_row(vt_node n) {
	return &n.rows->rows[n.index];
}

static inline bool vt_node_is_null(vt_node n) {
	return n.rows == NULL;
}

static inline bool vt_node_eq(vt_node a, vt_node b) {
	return a.rows == b.rows && a.index == b.index;
}

static inline uint32_t vt_node_start_byte(vt_node n) {
	return vt_node_row(n)->start_byte;
}

static inline uint32_t vt_node_end_byte(vt_node n) {
	return vt_node_row(n)->end_byte;
}

static inline vt_point vt_node_start_point(vt_node n) {
	vt_point p = {vt_node_row(n)->start_row, vt_node_row(n)->start_column};
	return p;
}

static inline vt_point vt_node_end_point(vt_node n) {
	vt_point p = {vt_node_row(n)->end_row, vt_node_row(n)->end_column};
	return p;
}

static inline uint16_t vt_node_symbol(vt_node n) {
	return vt_node_row(n)->symbol;
}

static inline uint16_t vt_node_field(vt_node n) {
	return vt_node_row(n)->field;
}

static inline bool vt_node_is_named(vt_node n) {
	return (vt_node_row(n)->flags & VT_ROW_NAMED) != 0;
}

static inline bool vt_node_is_extra(vt_node n) {
	return (vt_node_row(n)->flags & VT_ROW_EXTRA) != 0;
}

static inline bool vt_node_is_missing(vt_node n) {
	return (vt_node_row(n)->flags & VT_ROW_MISSING) != 0;
}

static inline bool vt_node_is_error(vt_node n) {
	return (vt_node_row(n)->flags & VT_ROW_ERROR) != 0;
}

static inline bool vt_node_has_error(vt_node n) {
	return (vt_node_row(n)->flags & VT_ROW_HAS_ERROR) != 0;
}

// vt_node_last is the index of the last row of the subtree.
static inline uint32_t vt_node_last(vt_node n) {
	return vt_node_row(n)->last;
}

static inline vt_node vt_node_or_null(const vt_rows *rows, uint32_t index) {
	return index == VT_ROW_NONE ? vt_node_null() : vt_node_at(rows, index);
}

static inline vt_node vt_node_parent(vt_node n) {
	return vt_node_or_null(n.rows, vt_node_row(n)->parent);
}

// vt_node_next is the next child of the node's parent, as the rows link them.
static inline vt_node vt_node_next(vt_node n) {
	return vt_node_or_null(n.rows, vt_node_row(n)->next);
}

// vt_node_next_sibling is ts_node_next_sibling, which finds the sibling by its range: it skips
// the siblings that end where the node ends (zero-width nodes: a MISSING node after an operator).
static inline vt_node vt_node_next_sibling(vt_node n) {
	const vt_row *rows = n.rows->rows;
	uint32_t end = rows[n.index].end_byte;
	for (uint32_t i = rows[n.index].next; i != VT_ROW_NONE; i = rows[i].next) {
		if (rows[i].end_byte > end) {
			return vt_node_at(n.rows, i);
		}
	}
	return vt_node_null();
}

static inline vt_node vt_node_prev_sibling(vt_node n) {
	return vt_node_or_null(n.rows, vt_node_row(n)->prev);
}

// vt_node_next_named_sibling is the next sibling that is named (a comment is), skipping those
// that end where the node ends as vt_node_next_sibling does.
static inline vt_node vt_node_next_named_sibling(vt_node n) {
	const vt_row *rows = n.rows->rows;
	uint32_t end = rows[n.index].end_byte;
	for (uint32_t i = rows[n.index].next; i != VT_ROW_NONE; i = rows[i].next) {
		if ((rows[i].flags & VT_ROW_NAMED) && rows[i].end_byte > end) {
			return vt_node_at(n.rows, i);
		}
	}
	return vt_node_null();
}

static inline vt_node vt_node_prev_named_sibling(vt_node n) {
	const vt_row *rows = n.rows->rows;
	for (uint32_t i = rows[n.index].prev; i != VT_ROW_NONE; i = rows[i].prev) {
		if (rows[i].flags & VT_ROW_NAMED) {
			return vt_node_at(n.rows, i);
		}
	}
	return vt_node_null();
}

// vt_node_first_child is the first child, also an anonymous one or a comment.
static inline vt_node vt_node_first_child(vt_node n) {
	const vt_row *row = vt_node_row(n);
	return row->last == n.index ? vt_node_null() : vt_node_at(n.rows, n.index + 1);
}

// vt_node_child_count counts the children, also the anonymous ones and the comments
// (ts_node_child_count).
static inline uint32_t vt_node_child_count(vt_node n) {
	const vt_row *rows = n.rows->rows;
	if (rows[n.index].last == n.index) {
		return 0;
	}
	uint32_t count = 0;
	for (uint32_t child = n.index + 1; child != VT_ROW_NONE; child = rows[child].next) {
		count++;
	}
	return count;
}

// vt_node_child is ts_node_child: the child at `i` among all of them.
static inline vt_node vt_node_child(vt_node n, uint32_t i) {
	const vt_row *rows = n.rows->rows;
	if (rows[n.index].last == n.index) {
		return vt_node_null();
	}
	for (uint32_t child = n.index + 1; child != VT_ROW_NONE; child = rows[child].next) {
		if (i == 0) {
			return vt_node_at(n.rows, child);
		}
		i--;
	}
	return vt_node_null();
}

// vt_node_named_child_count is ts_node_named_child_count: the named children, comments included.
static inline uint32_t vt_node_named_child_count(vt_node n) {
	const vt_row *rows = n.rows->rows;
	if (rows[n.index].last == n.index) {
		return 0;
	}
	uint32_t count = 0;
	for (uint32_t child = n.index + 1; child != VT_ROW_NONE; child = rows[child].next) {
		if (rows[child].flags & VT_ROW_NAMED) {
			count++;
		}
	}
	return count;
}

// vt_node_named_child is ts_node_named_child, with its quirk: an anonymous child that has named
// children (an anonymous alias of a rule) is not counted by ts_node_named_child_count, but
// ts_node_named_child counts its named children among the parent's, in their place.
static inline vt_node vt_node_named_child(vt_node n, uint32_t i) {
	const vt_row *rows = n.rows->rows;
	for (;;) {
		if (rows[n.index].last == n.index) {
			return vt_node_null();
		}
		bool descended = false;
		uint32_t index = 0;
		for (uint32_t child = n.index + 1; child != VT_ROW_NONE; child = rows[child].next) {
			if (rows[child].flags & VT_ROW_NAMED) {
				if (index == i) {
					return vt_node_at(n.rows, child);
				}
				index++;
				continue;
			}
			uint32_t grandchildren = vt_node_named_child_count(vt_node_at(n.rows, child));
			if (i - index < grandchildren) {
				i -= index;
				n = vt_node_at(n.rows, child);
				descended = true;
				break;
			}
			index += grandchildren;
		}
		if (!descended) {
			return vt_node_null();
		}
	}
}

// vt_node_child_by_field_id is ts_node_child_by_field_id: the first child with that field.
static inline vt_node vt_node_child_by_field_id(vt_node n, uint16_t field) {
	const vt_row *rows = n.rows->rows;
	if (field == 0 || rows[n.index].last == n.index) {
		return vt_node_null();
	}
	for (uint32_t child = n.index + 1; child != VT_ROW_NONE; child = rows[child].next) {
		if (rows[child].field == field) {
			return vt_node_at(n.rows, child);
		}
	}
	return vt_node_null();
}

// vt_node_descendant_count is ts_node_descendant_count: the node and its descendants.
static inline uint32_t vt_node_descendant_count(vt_node n) {
	return vt_node_row(n)->last - n.index + 1;
}

static inline bool vt_rows_has_error(const vt_rows *rows) {
	return rows->count > 0 && (rows->rows[0].flags & VT_ROW_HAS_ERROR) != 0;
}

// The rows written to a file and read back (treesitter.v, VESLINT_ROWS_STUB): each row's values
// as a parser gives them (no next, prev or last), read back the way a parser fills new rows.
#define VT_ROWS_MAGIC 0x31575256u // "VRW1"

typedef struct {
	uint32_t start_byte;
	uint32_t end_byte;
	uint32_t start_row;
	uint32_t start_column;
	uint32_t end_row;
	uint32_t end_column;
	uint32_t parent;
	uint16_t symbol;
	uint16_t field;
	uint32_t flags;
} vt_row_record;

static bool vt_rows_dump(const vt_rows *rows, const char *path) {
	FILE *out = fopen(path, "wb");
	if (out == NULL) {
		return false;
	}
	uint32_t header[2] = {VT_ROWS_MAGIC, rows->count};
	bool ok = fwrite(header, sizeof header, 1, out) == 1;
	for (uint32_t i = 0; ok && i < rows->count; i++) {
		const vt_row *row = &rows->rows[i];
		vt_row_record record = {row->start_byte, row->end_byte, row->start_row, row->start_column,
			row->end_row, row->end_column, row->parent, row->symbol, row->field, row->flags};
		ok = fwrite(&record, sizeof record, 1, out) == 1;
	}
	return fclose(out) == 0 && ok;
}

static vt_rows *vt_rows_load(const char *path, const void *language) {
	FILE *in = fopen(path, "rb");
	if (in == NULL) {
		return NULL;
	}
	uint32_t header[2];
	vt_rows *rows = NULL;
	if (fread(header, sizeof header, 1, in) == 1 && header[0] == VT_ROWS_MAGIC) {
		rows = vt_rows_new(language, header[1]);
	}
	for (uint32_t i = 0; rows != NULL && i < header[1]; i++) {
		vt_row_record record;
		if (fread(&record, sizeof record, 1, in) != 1) {
			vt_rows_free(rows);
			rows = NULL;
			break;
		}
		vt_row *row = &rows->rows[rows->count++];
		row->start_byte = record.start_byte;
		row->end_byte = record.end_byte;
		row->start_row = record.start_row;
		row->start_column = record.start_column;
		row->end_row = record.end_row;
		row->end_column = record.end_column;
		row->parent = record.parent;
		row->symbol = record.symbol;
		row->field = record.field;
		row->flags = (uint8_t)record.flags;
	}
	fclose(in);
	if (rows != NULL && !vt_rows_link(rows)) {
		vt_rows_free(rows);
		return NULL;
	}
	return rows;
}

#endif
