module tsgo

import os
import time

// TypeScript inside veslint's process: libveslint_tsgo.a (tsgo/inproc/, built by
// tsgo/inproc/build.sh) is TypeScript's API session compiled from the commit of the npm package
// veslint pins, as a C archive. A request is a function call that returns the payload the stdio
// server of `tsc --api` would have written, so the rest of the client decodes it as before; only
// the transport changes. The process transport stays behind VESLINT_TSGO=process.

#flag -I @VMODROOT/tsgo/inproc
#flag @VMODROOT/tsgo/inproc/out/libveslint_tsgo.a
#flag linux -lpthread -lm
#flag windows -lws2_32 -lwinmm -lntdll -luserenv -lbcrypt -lsynchronization
#include "veslint_tsgo.h"

struct C.veslint_tsgo_call {
mut:
	op      int
	handle  i64
	a       &char = unsafe { nil }
	a_len   uint
	b       &char = unsafe { nil }
	b_len   uint
	c       &char = unsafe { nil }
	c_len   uint
	flag    int
	out     &char = unsafe { nil }
	out_len uint
	result  i64
}

fn C.veslint_tsgo_invoke(call &C.veslint_tsgo_call)

// The operations of veslint_tsgo.h.
const op_open = 0
const op_request = 1
const op_serve = 2
const op_stop_serving = 3
const op_set_virtual = 4
const op_close = 5

// Transport is how veslint talks to TypeScript.
pub enum Transport {
	inproc  // TypeScript linked into veslint (the default)
	process // `tsc --api` over a pipe
}

// transport_from_env is VESLINT_TSGO: `process`, or `inproc` (the default, also when it is empty).
pub fn transport_from_env() !Transport {
	value := os.getenv('VESLINT_TSGO').trim_space()
	return match value {
		'', 'inproc' { Transport.inproc }
		'process' { Transport.process }
		else { error('VESLINT_TSGO must be `inproc` or `process` (got `${value}`)') }
	}
}

// inproc_out copies what Go handed back (malloc'd) into a V string and frees it.
fn inproc_out(call &C.veslint_tsgo_call) string {
	text := unsafe { (&u8(call.out)).vbytes(int(call.out_len)).bytestr() }
	unsafe { C.free(call.out) }
	return text
}

// start_inproc starts TypeScript's API session in this process as start_process_with starts `tsc
// --api`, with the same callbacks (answered in Go from the files the client gives it, see
// api_inprocess.go). The lib.*.d.ts files are those next to the binary `bin` of the process
// transport when they are there, so that their paths are the ones `tsc --api` gives; otherwise
// the ones embedded in the archive (the same files, under `bundled:///libs/`).
fn start_inproc(bin string, cwd string, timeout time.Duration, files map[string]string, callbacks bool, virtual_fs bool) !&Client {
	bin_dir := os.dir(bin)
	lib := if os.is_file(os.join_path(bin_dir, 'lib.d.ts')) { bin_dir } else { '' }
	names := if virtual_fs {
		'readFile,fileExists,stat,getAccessibleEntries'
	} else if callbacks {
		'readFile'
	} else {
		''
	}
	mut call := C.veslint_tsgo_call{
		op:    op_open
		a:     &char(cwd.str)
		a_len: uint(cwd.len)
		b:     &char(lib.str)
		b_len: uint(lib.len)
		c:     &char(names.str)
		c_len: uint(names.len)
	}
	C.veslint_tsgo_invoke(&call)
	if call.result == 0 {
		return error('could not start TypeScript: ${inproc_out(&call)}')
	}
	mut c := &Client{
		inproc:       call.result
		timeout:      timeout
		served:       served_by_key(files)
		serves_files: callbacks
		virtual_fs:   virtual_fs
	}
	for path, text in files {
		c.inproc_serve(path, text)
	}
	return c
}

// inproc_request is request for TypeScript in this process. A call cannot be interrupted, so
// the timeout of the process transport does not apply.
fn (mut c Client) inproc_request(method string, payload string) !string {
	mut call := C.veslint_tsgo_call{
		op:     op_request
		handle: c.inproc
		a:      &char(method.str)
		a_len:  uint(method.len)
		b:      &char(payload.str)
		b_len:  uint(payload.len)
	}
	C.veslint_tsgo_invoke(&call)
	c.requests++
	answer := inproc_out(&call)
	if call.result == i64(msg_response) {
		return answer
	}
	if call.result == i64(msg_error) {
		return error('tsgo rejected `${method}`: ${answer}')
	}
	c.shutdown()
	return error('TypeScript failed during `${method}`: ${answer}')
}

fn (c &Client) inproc_serve(path string, text string) {
	call := C.veslint_tsgo_call{
		op:     op_serve
		handle: c.inproc
		a:      &char(path.str)
		a_len:  uint(path.len)
		b:      &char(text.str)
		b_len:  uint(text.len)
	}
	C.veslint_tsgo_invoke(&call)
}

fn (c &Client) inproc_stop_serving(path string) {
	call := C.veslint_tsgo_call{
		op:     op_stop_serving
		handle: c.inproc
		a:      &char(path.str)
		a_len:  uint(path.len)
	}
	C.veslint_tsgo_invoke(&call)
}

fn (c &Client) inproc_set_virtual(path string, on bool) {
	call := C.veslint_tsgo_call{
		op:     op_set_virtual
		handle: c.inproc
		a:      &char(path.str)
		a_len:  uint(path.len)
		flag:   if on { 1 } else { 0 }
	}
	C.veslint_tsgo_invoke(&call)
}

fn (c &Client) inproc_close() {
	call := C.veslint_tsgo_call{
		op:     op_close
		handle: c.inproc
	}
	C.veslint_tsgo_invoke(&call)
}
