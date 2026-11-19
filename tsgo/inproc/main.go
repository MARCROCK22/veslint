// Command veslint_tsgo is TypeScript's API session (api.InProcess) as a C archive that veslint links
// (tsgo/inproc.c.v). veslint's build (tsgo/inproc/build.sh) makes it a module whose path is under
// the TypeScript module's (…/tsc/veslint_tsgo), so that it may import internal packages.
//
// Every function takes the bytes it is given by pointer and length and copies them; what it hands
// back is malloc'd and freed by the caller with veslint_tsgo_free. A session is named by a handle,
// since C may not keep Go pointers.
package main

/*
#include <stdlib.h>
#include <string.h>
*/
import "C"

import (
	"os"
	"runtime/debug"
	"strings"
	"sync"
	"unsafe"

	"github.com/microsoft/TypeScript/tsc/internal/api"
)

var (
	sessionsMu sync.RWMutex
	sessions   = map[int64]*api.InProcess{}
	lastHandle int64
)

func goString(p *C.char, n C.size_t) string {
	if n == 0 {
		return ""
	}
	return string(unsafe.Slice((*byte)(unsafe.Pointer(p)), int(n)))
}

func goBytes(p *C.char, n C.size_t) []byte {
	if n == 0 {
		return []byte{}
	}
	return append([]byte(nil), unsafe.Slice((*byte)(unsafe.Pointer(p)), int(n))...)
}

// cBytes copies `b` to C memory; *out is never NULL so that the caller always frees it.
func cBytes(b []byte, out **C.char, outLen *C.size_t) {
	p := C.malloc(C.size_t(len(b) + 1))
	if len(b) > 0 {
		C.memcpy(p, unsafe.Pointer(&b[0]), C.size_t(len(b)))
	}
	*out = (*C.char)(p)
	*outLen = C.size_t(len(b))
}

func session(handle C.longlong) *api.InProcess {
	sessionsMu.RLock()
	defer sessionsMu.RUnlock()
	return sessions[int64(handle)]
}

// veslint_tsgo_open starts a session as `tsc --api --cwd <cwd> [--callbacks=<callbacks>]` does.
// `lib` is the directory of the lib.*.d.ts files, empty for the embedded ones. It returns the
// handle, or 0 with the error in *err.
//
//export veslint_tsgo_open
func veslint_tsgo_open(cwd *C.char, cwdLen C.size_t, lib *C.char, libLen C.size_t, callbacks *C.char, callbacksLen C.size_t, errOut **C.char, errLen *C.size_t) C.longlong {
	var names []string
	if list := goString(callbacks, callbacksLen); list != "" {
		names = strings.Split(list, ",")
	}
	p, err := api.NewInProcess(api.InProcessOptions{
		Cwd:                goString(cwd, cwdLen),
		DefaultLibraryPath: goString(lib, libLen),
		Callbacks:          names,
	})
	if err != nil {
		cBytes([]byte(err.Error()), errOut, errLen)
		return 0
	}
	sessionsMu.Lock()
	defer sessionsMu.Unlock()
	lastHandle++
	sessions[lastHandle] = p
	return C.longlong(lastHandle)
}

// veslint_tsgo_request answers a request: it returns the message type of the msgpack protocol (4
// a response, 5 an error, 0 a failure that closes the connection) and the payload in *out.
// `worker` is 0 for the session's API checker, or the lint worker that asks (InProcess.Request).
//
//export veslint_tsgo_request
func veslint_tsgo_request(handle C.longlong, worker C.int, method *C.char, methodLen C.size_t, payload *C.char, payloadLen C.size_t, out **C.char, outLen *C.size_t) C.int {
	p := session(handle)
	if p == nil {
		cBytes([]byte("the TypeScript session is closed"), out, outLen)
		return 0
	}
	messageType, answer := p.Request(int(worker), goString(method, methodLen), goBytes(payload, payloadLen))
	cBytes(answer, out, outLen)
	return C.int(messageType)
}

// veslint_tsgo_serve makes `text` the content of `path` for the readFile callback.
//
//export veslint_tsgo_serve
func veslint_tsgo_serve(handle C.longlong, path *C.char, pathLen C.size_t, text *C.char, textLen C.size_t) {
	if p := session(handle); p != nil {
		p.Files().Serve(goString(path, pathLen), goString(text, textLen))
	}
}

// veslint_tsgo_stop_serving makes `path` read from disk again.
//
//export veslint_tsgo_stop_serving
func veslint_tsgo_stop_serving(handle C.longlong, path *C.char, pathLen C.size_t) {
	if p := session(handle); p != nil {
		p.Files().StopServing(goString(path, pathLen))
	}
}

// veslint_tsgo_set_virtual makes `path` a file that is not on disk (on != 0) or no longer one.
//
//export veslint_tsgo_set_virtual
func veslint_tsgo_set_virtual(handle C.longlong, path *C.char, pathLen C.size_t, on C.int) {
	if p := session(handle); p != nil {
		if on != 0 {
			p.Files().AddVirtual(goString(path, pathLen))
		} else {
			p.Files().RemoveVirtual(goString(path, pathLen))
		}
	}
}

// veslint_tsgo_close closes the session of `handle`.
//
//export veslint_tsgo_close
func veslint_tsgo_close(handle C.longlong) {
	sessionsMu.Lock()
	p := sessions[int64(handle)]
	delete(sessions, int64(handle))
	sessionsMu.Unlock()
	if p != nil {
		p.Close()
	}
}

// veslint_tsgo_free frees what the other functions handed back.
//
//export veslint_tsgo_free
func veslint_tsgo_free(p *C.char) {
	C.free(unsafe.Pointer(p))
}

// gcPercent is the GOGC of TypeScript in veslint when the environment does not set one. At Go's
// default (100) its collector took a fifth of TypeScript's time in a lint of zod. With two workers,
// 200 lints zod and recharts 6 % faster for 7 % more memory, and the TypeScript compiler 2 % faster
// for 19 % more (2.9 GiB instead of 2.4); 400 is 5 % faster there and holds 3.2 GiB.
const gcPercent = 200

func init() {
	if os.Getenv("GOGC") == "" {
		debug.SetGCPercent(gcPercent)
	}
}

func main() {}
