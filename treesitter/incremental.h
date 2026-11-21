// Incremental parsing (treesitter.v, Parser.reparse): the edit that turns one text into another,
// for ts_tree_edit, and a comparison of two trees node by node, to check that a tree parsed
// incrementally is the one a parse from scratch gives.
#ifndef VESLINT_INCREMENTAL_H
#define VESLINT_INCREMENTAL_H

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "tree_sitter/api.h"

static bool vt_utf8_continuation(const char *text, uint32_t length, uint32_t at) {
	return at < length && (((unsigned char)text[at]) & 0xC0) == 0x80;
}

// vt_point_after is the point of `text[at]` from the point of `text[from]` (from <= at): tree-sitter
// counts a row at each `\n` only, and columns in bytes.
static TSPoint vt_point_after(const char *text, uint32_t from, TSPoint point, uint32_t at) {
	const char *cursor = text + from;
	const char *end = text + at;
	const char *line = NULL;
	while (cursor < end) {
		const char *nl = (const char *)memchr(cursor, '\n', (size_t)(end - cursor));
		if (nl == NULL) {
			break;
		}
		point.row++;
		line = nl + 1;
		cursor = nl + 1;
	}
	if (line == NULL) {
		point.column += at - from;
	} else {
		point.column = (uint32_t)(end - line);
	}
	return point;
}

// vt_text_edit fills `edit` with the change from `old_text` to `new_text`: the bytes they have in
// common at the start and at the end are kept, the rest is the edited range, moved to the
// boundaries of the UTF-8 characters around it. Returns false when the texts are equal.
static bool vt_text_edit(const char *old_text, uint32_t old_length, const char *new_text,
	uint32_t new_length, TSInputEdit *edit) {
	uint32_t shorter = old_length < new_length ? old_length : new_length;
	uint32_t prefix = 0;
	// Whole words first, then the bytes.
	while (prefix + sizeof(uint64_t) <= shorter
		&& memcmp(old_text + prefix, new_text + prefix, sizeof(uint64_t)) == 0) {
		prefix += sizeof(uint64_t);
	}
	while (prefix < shorter && old_text[prefix] == new_text[prefix]) {
		prefix++;
	}
	if (prefix == old_length && prefix == new_length) {
		return false;
	}
	while (prefix > 0 && (vt_utf8_continuation(old_text, old_length, prefix)
		|| vt_utf8_continuation(new_text, new_length, prefix))) {
		prefix--;
	}
	uint32_t suffix = 0;
	uint32_t room = shorter - prefix;
	while (suffix < room && old_text[old_length - 1 - suffix] == new_text[new_length - 1 - suffix]) {
		suffix++;
	}
	// The kept end starts at a character: the same bytes in both texts.
	while (suffix > 0 && vt_utf8_continuation(old_text, old_length, old_length - suffix)) {
		suffix--;
	}
	TSPoint origin = {0, 0};
	edit->start_byte = prefix;
	edit->old_end_byte = old_length - suffix;
	edit->new_end_byte = new_length - suffix;
	edit->start_point = vt_point_after(old_text, 0, origin, prefix);
	edit->old_end_point = vt_point_after(old_text, prefix, edit->start_point, edit->old_end_byte);
	edit->new_end_point = vt_point_after(new_text, prefix, edit->start_point, edit->new_end_byte);
	return true;
}

// The kinds of nodes whose children are statements or members: the window of an edit is made of
// the children of the closest one around it (vt_edit_window).
static const char *vt_container_kinds[] = {"program", "statement_block", "class_body", "switch_body",
	"switch_case", "switch_default", "object_type", "interface_body", "enum_body"};
#define VT_CONTAINER_KINDS (sizeof(vt_container_kinds) / sizeof(vt_container_kinds[0]))

static bool vt_is_container(TSNode node) {
	const char *kind = ts_node_type(node);
	for (size_t i = 0; i < VT_CONTAINER_KINDS; i++) {
		if (strcmp(kind, vt_container_kinds[i]) == 0) {
			return true;
		}
	}
	return false;
}

// vt_edit_window is the range, in the edited tree, of the statements or members around an edit:
// the children of the closest container node around the edited range that overlap or touch it.
static void vt_edit_window(const TSTree *tree, const TSInputEdit *edit, uint32_t *start, uint32_t *end) {
	TSNode root = ts_tree_root_node(tree);
	TSNode node = ts_node_descendant_for_byte_range(root, edit->start_byte, edit->new_end_byte);
	while (!ts_node_is_null(node) && !vt_is_container(node)) {
		node = ts_node_parent(node);
	}
	if (ts_node_is_null(node)) {
		node = root;
	}
	*start = edit->start_byte;
	*end = edit->new_end_byte;
	// A cursor: ts_node_child walks from the first child at every call.
	TSTreeCursor cursor = ts_tree_cursor_new(node);
	for (bool more = ts_tree_cursor_goto_first_child(&cursor); more;
		more = ts_tree_cursor_goto_next_sibling(&cursor)) {
		TSNode child = ts_tree_cursor_current_node(&cursor);
		uint32_t child_start = ts_node_start_byte(child);
		uint32_t child_end = ts_node_end_byte(child);
		if (child_end < edit->start_byte || child_start > edit->new_end_byte) {
			continue;
		}
		if (child_start < *start) {
			*start = child_start;
		}
		if (child_end > *end) {
			*end = child_end;
		}
	}
	ts_tree_cursor_delete(&cursor);
}

#define VT_REPARSE_SAME 0 // the texts are equal: the tree is the old one
#define VT_REPARSE_INCREMENTAL 1 // parsed from the old tree
#define VT_REPARSE_FRESH 2 // parsed from scratch: the old tree could not be trusted for this edit

// vt_reparse parses `new_text` from `old`, the tree of `old_text`, which it takes (frees, or gives
// back for equal texts), and tells how in `outcome`; NULL when tree-sitter cannot parse it.
//
// tree-sitter's incremental parse does not always give the tree of a parse from scratch: where the
// grammar is ambiguous, the subtrees it reuses may settle the ambiguity otherwise (`}` of a
// function followed by a line `-1;` read as a subtraction from a function expression, far from
// the edit), and its error recovery depends on what came before. So the incremental tree is kept
// only when neither tree has an error and every range whose structure changed
// (ts_tree_get_changed_ranges) is in the statements or members around the edit; otherwise the
// text is parsed from scratch.
static TSTree *vt_reparse(TSParser *parser, TSTree *old, const char *old_text, uint32_t old_length,
	const char *new_text, uint32_t new_length, int *outcome) {
	TSInputEdit edit;
	if (!vt_text_edit(old_text, old_length, new_text, new_length, &edit)) {
		*outcome = VT_REPARSE_SAME;
		return old;
	}
	*outcome = VT_REPARSE_FRESH;
	if (ts_node_has_error(ts_tree_root_node(old))) {
		ts_tree_delete(old);
		return ts_parser_parse_string(parser, NULL, new_text, new_length);
	}
	ts_tree_edit(old, &edit);
	uint32_t window_start = 0;
	uint32_t window_end = 0;
	vt_edit_window(old, &edit, &window_start, &window_end);
	TSTree *tree = ts_parser_parse_string(parser, old, new_text, new_length);
	bool trusted = tree != NULL && !ts_node_has_error(ts_tree_root_node(tree));
	if (trusted) {
		uint32_t count = 0;
		TSRange *ranges = ts_tree_get_changed_ranges(old, tree, &count);
		for (uint32_t i = 0; i < count && trusted; i++) {
			trusted = ranges[i].start_byte >= window_start && ranges[i].end_byte <= window_end;
		}
		free(ranges);
	}
	ts_tree_delete(old);
	if (trusted) {
		*outcome = VT_REPARSE_INCREMENTAL;
		return tree;
	}
	if (tree != NULL) {
		ts_tree_delete(tree);
	}
	return ts_parser_parse_string(parser, NULL, new_text, new_length);
}

static bool vt_points_equal(TSPoint a, TSPoint b) {
	return a.row == b.row && a.column == b.column;
}

// vt_nodes_alike: the two nodes are the same node of two trees of one text (their children apart).
static bool vt_nodes_alike(TSNode a, TSNode b) {
	return ts_node_symbol(a) == ts_node_symbol(b) && ts_node_grammar_symbol(a) == ts_node_grammar_symbol(b)
		&& ts_node_start_byte(a) == ts_node_start_byte(b) && ts_node_end_byte(a) == ts_node_end_byte(b)
		&& vt_points_equal(ts_node_start_point(a), ts_node_start_point(b))
		&& vt_points_equal(ts_node_end_point(a), ts_node_end_point(b))
		&& ts_node_is_named(a) == ts_node_is_named(b) && ts_node_is_missing(a) == ts_node_is_missing(b)
		&& ts_node_is_extra(a) == ts_node_is_extra(b) && ts_node_is_error(a) == ts_node_is_error(b)
		&& ts_node_has_error(a) == ts_node_has_error(b) && ts_node_child_count(a) == ts_node_child_count(b);
}

// vt_trees_differ compares two trees node by node, in preorder: the start byte of the first node
// that differs (its kind, range, flags, field or number of children), or -1 when they are equal.
static int64_t vt_trees_differ(const TSTree *a, const TSTree *b) {
	TSTreeCursor ca = ts_tree_cursor_new(ts_tree_root_node(a));
	TSTreeCursor cb = ts_tree_cursor_new(ts_tree_root_node(b));
	int64_t result = -1;
	for (;;) {
		TSNode na = ts_tree_cursor_current_node(&ca);
		TSNode nb = ts_tree_cursor_current_node(&cb);
		if (!vt_nodes_alike(na, nb)
			|| ts_tree_cursor_current_field_id(&ca) != ts_tree_cursor_current_field_id(&cb)) {
			result = (int64_t)ts_node_start_byte(na);
			break;
		}
		// The same number of children: the cursors move alike.
		if (ts_tree_cursor_goto_first_child(&ca)) {
			ts_tree_cursor_goto_first_child(&cb);
			continue;
		}
		bool next = false;
		for (;;) {
			if (ts_tree_cursor_goto_next_sibling(&ca)) {
				ts_tree_cursor_goto_next_sibling(&cb);
				next = true;
				break;
			}
			if (!ts_tree_cursor_goto_parent(&ca)) {
				break;
			}
			ts_tree_cursor_goto_parent(&cb);
		}
		if (!next) {
			break;
		}
	}
	ts_tree_cursor_delete(&ca);
	ts_tree_cursor_delete(&cb);
	return result;
}

#endif
