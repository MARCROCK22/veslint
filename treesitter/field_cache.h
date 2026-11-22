// The field id of each field name, remembered per thread. ts_language_field_id_for_name looks the
// name up among the grammar's field names with strncmp every time, and the rules ask node_field
// for fields millions of times in a large project; the id of a name never changes for a grammar.
#ifndef VESLINT_FIELD_CACHE_H
#define VESLINT_FIELD_CACHE_H

#include <stdint.h>
#include <string.h>
#include "tree_sitter/api.h"
#include "rows.h"

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

// vt_node_child_by_field_name is ts_node_child_by_field_name on the rows: the first child with
// that field.
static vt_node vt_node_child_by_field_name(vt_node self, const char *name, uint32_t length) {
	TSFieldId id = vt_field_id((const TSLanguage *)self.rows->language, name, length);
	return vt_node_child_by_field_id(self, id);
}

#endif
