// The field id of each field name, remembered per thread. ts_node_child_by_field_name looks the name
// up among the grammar's field names with strncmp every time, and the rules ask node_field for
// fields millions of times in a large project; the id of a name never changes for a grammar.
#ifndef VESLINT_FIELD_CACHE_H
#define VESLINT_FIELD_CACHE_H

#include <stdint.h>
#include <string.h>
#include "tree_sitter/api.h"
#include "flat_tree.h"

#define VT_FC_SLOTS 512
#define VT_FC_NAME 40

typedef struct {
	const TSLanguage *language; // NULL for an empty slot
	uint32_t length;
	TSFieldId id;
	char name[VT_FC_NAME];
} vt_field_slot;

static _Thread_local vt_field_slot vt_fc_slots[VT_FC_SLOTS];

// vt_field_id is ts_language_field_id_for_name(language, name, length).
static TSFieldId vt_field_id(const TSLanguage *language, const char *name, uint32_t length) {
	if (length >= VT_FC_NAME) {
		return ts_language_field_id_for_name(language, name, length);
	}
	uint64_t h = 1469598103934665603ULL ^ (uint64_t)(uintptr_t)language;
	for (uint32_t i = 0; i < length; i++) {
		h = (h ^ (unsigned char)name[i]) * 1099511628211ULL;
	}
	vt_field_slot *slot = &vt_fc_slots[(h ^ (h >> 29)) & (VT_FC_SLOTS - 1)];
	if (slot->language == language && slot->length == length && memcmp(slot->name, name, length) == 0) {
		return slot->id;
	}
	TSFieldId id = ts_language_field_id_for_name(language, name, length);
	slot->language = language;
	slot->length = length;
	slot->id = id;
	memcpy(slot->name, name, length);
	return id;
}

// vt_node_child_by_field_name is ts_node_child_by_field_name with the field ids remembered and,
// for a node of the flat tree (flat_tree.h), its answers too: the rules ask the same fields of the
// same nodes again and again (each rule walks the file), and ts_node_child_by_field_id walks the
// children (through the hidden ones) at every call. Only the answers of tree-sitter are kept, so
// they are the same: a child that the table does not have as tree-sitter gives it is not kept.
static TSNode vt_node_child_by_field_name(TSNode self, const char *name, uint32_t length) {
	TSFieldId id = vt_field_id(ts_node_language(self), name, length);
	int64_t index = vt_flat_find(self);
	if (index < 0) {
		return ts_node_child_by_field_id(self, id);
	}
	vt_flat_node *entry = &vt_ft_nodes[index];
	for (uint8_t k = 0; k < entry->asked; k++) {
		if (entry->asked_field[k] == id) {
			uint32_t answer = entry->answer[k];
			if (answer == VT_FLAT_NONE) {
				TSNode none;
				memset(&none, 0, sizeof none);
				return none;
			}
			return vt_ft_nodes[answer].node;
		}
	}
	TSNode child = ts_node_child_by_field_id(self, id);
	uint32_t answer = VT_FLAT_NONE;
	if (!ts_node_is_null(child)) {
		int64_t at = vt_flat_find(child);
		if (at < 0 || memcmp(&vt_ft_nodes[at].node, &child, sizeof child) != 0) {
			return child;
		}
		answer = (uint32_t)at;
	} else {
		TSNode none;
		memset(&none, 0, sizeof none);
		if (memcmp(&none, &child, sizeof child) != 0) {
			return child;
		}
	}
	// The first fields asked stay; later ones take the last slot.
	uint8_t slot = entry->asked < VT_FLAT_FIELDS ? entry->asked++ : VT_FLAT_FIELDS - 1;
	entry->asked_field[slot] = id;
	entry->answer[slot] = answer;
	return child;
}

#endif
