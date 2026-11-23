// veslint_tsgo.h: the functions of libveslint_tsgo.a (tsgo/inproc/main.go) and how veslint calls
// them (tsgo/inproc.c.v). The prototypes are written here instead of including the header `go
// build` writes, which needs the Go toolchain's types.
#ifndef VESLINT_TSGO_H
#define VESLINT_TSGO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

extern long long veslint_tsgo_open(char* cwd, size_t cwd_len, char* lib, size_t lib_len, char* callbacks,
	size_t callbacks_len, char** err, size_t* err_len);
extern int veslint_tsgo_request(long long handle, int worker, char* method, size_t method_len, char* payload,
	size_t payload_len, char** out, size_t* out_len);
extern void veslint_tsgo_serve(long long handle, char* path, size_t path_len, char* text, size_t text_len);
extern void veslint_tsgo_stop_serving(long long handle, char* path, size_t path_len);
extern void veslint_tsgo_set_virtual(long long handle, char* path, size_t path_len, int on);
extern void veslint_tsgo_close(long long handle);
extern void veslint_tsgo_free(char* p);

// The converter from TypeScript's AST to the rows of tree-sitter's tree (tsgo/inproc/convert.go):
// a row is a visible node of the tree tree-sitter's parse of the text gives, in preorder, with the
// values tree-sitter's API gives for it (symbol, field id, flags, byte range, points with columns
// in bytes) and its parent, next and previous siblings and the last row of its subtree
// (VESLINT_TSGO_ROW_NONE for none). The layout is the vt_row of veslint's rows.
#define VESLINT_TSGO_ROW_NONE UINT32_MAX
#define VESLINT_TSGO_ROW_NAMED 1
#define VESLINT_TSGO_ROW_EXTRA 2
#define VESLINT_TSGO_ROW_MISSING 4
#define VESLINT_TSGO_ROW_ERROR 8
#define VESLINT_TSGO_ROW_HAS_ERROR 16
typedef struct {
	uint32_t start_byte, end_byte, start_row, start_column, end_row, end_column;
	uint32_t parent, next, prev, last;
	uint16_t symbol, field;
	uint8_t flags;
} veslint_tsgo_row;

// ts_language_symbol_for_name and ts_language_field_id_for_name, with the language as `const void*`.
typedef uint16_t (*veslint_tsgo_symbol_fn)(const void* language, const char* name, uint32_t length, bool named);
typedef uint16_t (*veslint_tsgo_field_fn)(const void* language, const char* name, uint32_t length);

// veslint_tsgo_convert_language gives the converter the tables of a language (tsx 0: TypeScript, 1:
// TSX) once, before its first veslint_tsgo_convert.
extern int veslint_tsgo_convert_language(int tsx, void* language, veslint_tsgo_symbol_fn symbol,
	veslint_tsgo_field_fn field);

// The results of veslint_tsgo_convert.
enum {
	veslint_tsgo_convert_rows = 0, // *rows has *count rows, freed with veslint_tsgo_free
	veslint_tsgo_convert_diagnostics = 1, // TypeScript reports parse diagnostics: *rows is their text (*count bytes), freed with veslint_tsgo_free
	veslint_tsgo_convert_failed = 2, // the converter failed: no rows
	veslint_tsgo_convert_no_language = 3, // no veslint_tsgo_convert_language for the language
};

// veslint_tsgo_convert converts one file (flags: 1 for TSX, plus 2 for ESLint's sourceType
// "script"), its text without a BOM.
extern int veslint_tsgo_convert(int flags, char* text, size_t text_len, veslint_tsgo_row** rows, size_t* count);
// veslint_tsgo_convert_file is veslint_tsgo_convert for a file of a program of the session
// `handle`, whose AST it converts when it is the one a parse of the text gives: `params` name the
// snapshot, the project and the file as the parameters of veslint/nodesAtRanges, without values.
extern int veslint_tsgo_convert_file(long long handle, char* params, size_t params_len, int flags, char* text,
	size_t text_len, veslint_tsgo_row** rows, size_t* count);

// Boehm's GC_do_blocking, declared here: V calls its collector through wrappers of its own and the
// C it generates does not include gc.h, so without this the call was an implicit declaration (a
// warning of gcc 11, an error of gcc 14, the one of the Windows build). The signature is gc.h's.
#ifndef GC_H
extern void* GC_do_blocking(void* (*fn)(void*), void* client_data);
#endif

// A call into Go runs on a goroutine stack, which V's garbage collector (Boehm, which stops a
// thread with a signal and scans its stack from the stack pointer the signal finds) cannot scan.
// So every call is made with GC_do_blocking: while Go runs, the collector does not stop the
// thread and scans its stack only above the call, where the arguments are. Go copies what it is
// given before it returns and touches no memory of V's heap afterwards.
struct veslint_tsgo_call {
	int op;
	long long handle;
	char* a;
	size_t a_len;
	char* b;
	size_t b_len;
	char* c;
	size_t c_len;
	int flag;
	char* out;
	size_t out_len;
	long long result;
};

enum {
	veslint_tsgo_op_open,
	veslint_tsgo_op_request,
	veslint_tsgo_op_serve,
	veslint_tsgo_op_stop_serving,
	veslint_tsgo_op_set_virtual,
	veslint_tsgo_op_close,
	veslint_tsgo_op_convert_language,
	veslint_tsgo_op_convert,
	veslint_tsgo_op_convert_file,
};

static void* veslint_tsgo_run(void* data) {
	struct veslint_tsgo_call* call = (struct veslint_tsgo_call*)data;
	switch (call->op) {
	case veslint_tsgo_op_open:
		call->result = veslint_tsgo_open(call->a, call->a_len, call->b, call->b_len, call->c, call->c_len,
			&call->out, &call->out_len);
		break;
	case veslint_tsgo_op_request:
		call->result = veslint_tsgo_request(call->handle, call->flag, call->a, call->a_len, call->b, call->b_len,
			&call->out, &call->out_len);
		break;
	case veslint_tsgo_op_serve:
		veslint_tsgo_serve(call->handle, call->a, call->a_len, call->b, call->b_len);
		break;
	case veslint_tsgo_op_stop_serving:
		veslint_tsgo_stop_serving(call->handle, call->a, call->a_len);
		break;
	case veslint_tsgo_op_set_virtual:
		veslint_tsgo_set_virtual(call->handle, call->a, call->a_len, call->flag);
		break;
	case veslint_tsgo_op_close:
		veslint_tsgo_close(call->handle);
		break;
	// a: the language, b and c: its symbol and field functions, flag: tsx.
	case veslint_tsgo_op_convert_language:
		call->result = veslint_tsgo_convert_language(call->flag, call->a, (veslint_tsgo_symbol_fn)call->b,
			(veslint_tsgo_field_fn)call->c);
		break;
	// a: the text, flag: the flags; out and out_len: the rows and their count.
	case veslint_tsgo_op_convert:
		call->result = veslint_tsgo_convert(call->flag, call->a, call->a_len, (veslint_tsgo_row**)&call->out,
			&call->out_len);
		break;
	// handle: the session, a: the text, b: the snapshot, project and path (veslint_tsgo_convert_file),
	// flag: the flags; out and out_len as for veslint_tsgo_op_convert.
	case veslint_tsgo_op_convert_file:
		call->result = veslint_tsgo_convert_file(call->handle, call->b, call->b_len, call->flag, call->a, call->a_len,
			(veslint_tsgo_row**)&call->out, &call->out_len);
		break;
	}
	return NULL;
}

static void veslint_tsgo_invoke(struct veslint_tsgo_call* call) {
#if (defined(_VGCBOEHM) || defined(CUSTOM_DEFINE_gcboehm)) && defined(GC_THREADS)
	GC_do_blocking(veslint_tsgo_run, call);
#else
	veslint_tsgo_run(call);
#endif
}

#endif
