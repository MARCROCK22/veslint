// converter_tables.h: the lookups that the converter from TypeScript's AST (tsgo.convert_language,
// tsgo/inproc/veslint_tsgo.h) calls to find the symbols and fields of the grammar's languages: they
// take the language as `const void *`, the converter's type for it.
#ifndef VT_CONVERTER_TABLES_H
#define VT_CONVERTER_TABLES_H

#include <stdbool.h>
#include <stdint.h>
#include "tree_sitter/api.h"

static uint16_t vt_converter_symbol(const void *language, const char *name, uint32_t length, bool named) {
	return ts_language_symbol_for_name((const TSLanguage *)language, name, length, named);
}

static uint16_t vt_converter_field(const void *language, const char *name, uint32_t length) {
	return ts_language_field_id_for_name((const TSLanguage *)language, name, length);
}

static void *vt_converter_symbol_fn(void) {
	return (void *)vt_converter_symbol;
}

static void *vt_converter_field_fn(void) {
	return (void *)vt_converter_field;
}

#endif
