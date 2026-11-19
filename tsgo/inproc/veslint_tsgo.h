// veslint_tsgo.h: the functions of libveslint_tsgo.a (tsgo/inproc/main.go) and how veslint calls
// them (tsgo/inproc.c.v). The prototypes are written here instead of including the header `go
// build` writes, which needs the Go toolchain's types.
#ifndef VESLINT_TSGO_H
#define VESLINT_TSGO_H

#include <stddef.h>

extern long long veslint_tsgo_open(char* cwd, size_t cwd_len, char* lib, size_t lib_len, char* callbacks,
	size_t callbacks_len, char** err, size_t* err_len);
extern int veslint_tsgo_request(long long handle, int worker, char* method, size_t method_len, char* payload,
	size_t payload_len, char** out, size_t* out_len);
extern void veslint_tsgo_serve(long long handle, char* path, size_t path_len, char* text, size_t text_len);
extern void veslint_tsgo_stop_serving(long long handle, char* path, size_t path_len);
extern void veslint_tsgo_set_virtual(long long handle, char* path, size_t path_len, int on);
extern void veslint_tsgo_close(long long handle);
extern void veslint_tsgo_free(char* p);

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
