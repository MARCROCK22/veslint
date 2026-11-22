// veslint_tsgo_languages.h: gives the converter of libveslint_tsgo.a (veslint_tsgo.h,
// veslint_tsgo_convert) the tables of veslint's grammar, for the code that links tree-sitter (its
// api.h is included here; veslint_tsgo.h does not need it).
#ifndef VESLINT_TSGO_LANGUAGES_H
#define VESLINT_TSGO_LANGUAGES_H

#include "tree_sitter/api.h"
#include "veslint_tsgo.h"

const TSLanguage* tree_sitter_typescript(void);
const TSLanguage* tree_sitter_tsx(void);

static uint16_t veslint_tsgo_symbol_for_name(const void* language, const char* name, uint32_t length, bool named) {
	return ts_language_symbol_for_name((const TSLanguage*)language, name, length, named);
}

static uint16_t veslint_tsgo_field_for_name(const void* language, const char* name, uint32_t length) {
	return ts_language_field_id_for_name((const TSLanguage*)language, name, length);
}

// veslint_tsgo_convert_languages gives the converter both languages (call it once, before the
// first veslint_tsgo_convert).
static void veslint_tsgo_convert_languages(void) {
	for (int tsx = 0; tsx < 2; tsx++) {
		struct veslint_tsgo_call call = {0};
		call.op = veslint_tsgo_op_convert_language;
		call.flag = tsx;
		call.a = (char*)(tsx ? tree_sitter_tsx() : tree_sitter_typescript());
		call.b = (char*)veslint_tsgo_symbol_for_name;
		call.c = (char*)veslint_tsgo_field_for_name;
		veslint_tsgo_invoke(&call);
	}
}

#endif
