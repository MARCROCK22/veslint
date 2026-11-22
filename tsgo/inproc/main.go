// Command veslint_tsgo is TypeScript's API session (api.InProcess) as a C archive that veslint links
// (tsgo/inproc.c.v). veslint's build (tsgo/inproc/build.sh) makes it a module whose path is under
// the TypeScript module's (…/tsc/veslint_tsgo), so that it may import internal packages.
//
// Every function takes the bytes it is given by pointer and length and copies them; what it hands
// back is malloc'd and freed by the caller with veslint_tsgo_free. A session is named by a handle,
// since C may not keep Go pointers.
package main

/*
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// Keep in step with veslint_tsgo.h.
typedef struct {
	uint32_t start_byte, end_byte, start_row, start_column, end_row, end_column;
	uint32_t parent, next, prev, last;
	uint16_t symbol, field;
	uint8_t flags;
} veslint_tsgo_row;
typedef uint16_t (*veslint_tsgo_symbol_fn)(const void *language, const char *name, uint32_t length, bool named);
typedef uint16_t (*veslint_tsgo_field_fn)(const void *language, const char *name, uint32_t length);

static uint16_t veslint_tsgo_call_symbol(veslint_tsgo_symbol_fn f, const void *language, const char *name, uint32_t length, bool named) {
	return f(language, name, length, named);
}
static uint16_t veslint_tsgo_call_field(veslint_tsgo_field_fn f, const void *language, const char *name, uint32_t length) {
	return f(language, name, length);
}
*/
import "C"

import (
	"os"
	"runtime"
	"runtime/debug"
	"runtime/metrics"
	"strings"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/microsoft/TypeScript/tsc/internal/api"
	"github.com/microsoft/TypeScript/tsc/internal/parser"
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
	release_ballast()
	p := session(handle)
	if p == nil {
		cBytes([]byte("the TypeScript session is closed"), out, outLen)
		return 0
	}
	buffer := answerBuffers.Get().(*[]byte)
	messageType, answer := p.Request(int(worker), goString(method, methodLen), goBytes(payload, payloadLen), (*buffer)[:0])
	cBytes(answer, out, outLen)
	if cap(answer) <= maxPooledAnswer {
		*buffer = answer[:0]
		answerBuffers.Put(buffer)
	}
	return C.int(messageType)
}

// answerBuffers are the buffers the answers are written in before they are copied to C memory: a
// lint asks tens of thousands of questions, whose answers would otherwise be as many buffers for
// Go's collector. One that grew past maxPooledAnswer (the answer about a huge file) is dropped.
var answerBuffers = sync.Pool{New: func() any {
	buffer := make([]byte, 0, 64<<10)
	return &buffer
}}

const maxPooledAnswer = 4 << 20

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

// The converter from TypeScript's AST to the rows of tree-sitter's tree (convert.go, in
// internal/parser): the tables of each language, set once by veslint_tsgo_convert_language, and
// the converters, one per thread at a time.
var (
	convertLanguages [2]atomic.Pointer[parser.VeslintLanguage]
	converters       [2]sync.Pool
)

// veslint_tsgo_convert_language gives the converter the tables of a language of veslint's grammar
// (`tsx` 0: TypeScript, 1: TSX): `symbol` and `field` are ts_language_symbol_for_name and
// ts_language_field_id_for_name of `language` (a `const TSLanguage *`), called here and only here.
// It returns 0.
//
//export veslint_tsgo_convert_language
func veslint_tsgo_convert_language(tsx C.int, language unsafe.Pointer, symbol C.veslint_tsgo_symbol_fn, field C.veslint_tsgo_field_fn) C.int {
	l := parser.NewVeslintLanguage(tsx != 0, func(name string, named bool) uint16 {
		cs := C.CString(name)
		defer C.free(unsafe.Pointer(cs))
		return uint16(C.veslint_tsgo_call_symbol(symbol, language, cs, C.uint32_t(len(name)), C.bool(named)))
	}, func(name string) uint16 {
		cs := C.CString(name)
		defer C.free(unsafe.Pointer(cs))
		return uint16(C.veslint_tsgo_call_field(field, language, cs, C.uint32_t(len(name))))
	})
	convertLanguages[tsx&1].Store(l)
	return 0
}

// The results of veslint_tsgo_convert.
const (
	convertRows        = 0 // *rows has *count rows
	convertDiagnostics = 1 // TypeScript reports parse diagnostics: no rows (ESLint's "Parsing error")
	convertFailed      = 2 // the converter failed: no rows (the caller parses with tree-sitter)
	convertNoLanguage  = 3 // veslint_tsgo_convert_language was not called for the language
)

// veslint_tsgo_convert parses `text` with TypeScript's parser and writes the rows of
// tree-sitter's tree of it: one call per file. `flags` is 1 for TSX, plus 2 for ESLint's
// sourceType "script". On convertRows, *rows is a malloc'd array of *count veslint_tsgo_row in
// preorder (the caller frees it with veslint_tsgo_free); otherwise *rows is NULL.
//
//export veslint_tsgo_convert
func veslint_tsgo_convert(flags C.int, text *C.char, textLen C.size_t, rows **C.veslint_tsgo_row, count *C.size_t) (result C.int) {
	*rows = nil
	*count = 0
	tsx := flags & 1
	l := convertLanguages[tsx].Load()
	if l == nil {
		return convertNoLanguage
	}
	c, _ := converters[tsx].Get().(*parser.VeslintConverter)
	if c == nil {
		c = parser.NewVeslintConverter(l)
	}
	c.Script = flags&2 != 0
	defer func() {
		// A converter that panicked may hold any state: it is not reused.
		if r := recover(); r != nil {
			*rows = nil
			*count = 0
			result = convertFailed
			return
		}
		converters[tsx].Put(c)
	}()
	out, diagnostics := c.Convert(goString(text, textLen))
	if diagnostics {
		return convertDiagnostics
	}
	size := C.size_t(len(out)) * C.size_t(unsafe.Sizeof(parser.VeslintRow{}))
	p := C.malloc(max(size, 1))
	if p == nil {
		return convertFailed
	}
	if len(out) > 0 {
		C.memcpy(p, unsafe.Pointer(&out[0]), size)
	}
	*rows = (*C.veslint_tsgo_row)(p)
	*count = C.size_t(len(out))
	return convertRows
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

// gcBallast puts off Go's first collections. A lint builds the program and fills the checkers from
// nothing, and until then most of what Go has is still in use: GOGC's first collections (at 8 MiB,
// then each time the heap triples) walk it again and again. `ballast`, an array of that many bytes
// that is never written (so it takes no memory) and has no pointers (so the collector does not
// walk it), counts as live: with GOGC gcPercent the first collection comes when the heap reaches
// three times it, about 256 MiB besides the ballast. Once that collection has run, a request
// drops the ballast (release_ballast) and sets the GOGC that puts the next collection where
// gcPercent would without the ballast (the heap the collection kept, but the ballast, three
// times); once the next one has run, gcPercent. Requests notice the collections (by their count,
// every 64 requests) because nothing else is sure to run: a cleanup, a weak pointer (cleared when
// its span is swept) or the background sweeper need goroutines that may not run while veslint's
// threads keep taking Go's only P (VESLINT_CPUS=1). With two workers on the minipc, median of 3
// alternated runs against GOGC 200 alone: zod 2.52 -> 2.38 s (53 MB more), recharts 5.23 -> 4.69
// s (7 MB more), the TypeScript compiler the same (measured with GOGC off up to a GOMEMLIMIT of
// 256 MiB, the same first collection); GOGC off up to 512 MiB: zod 2.32 s with 129 MB more. A GOGC
// or GOMEMLIMIT in the environment is Go's alone.
const gcBallast = 128 << 20

// The steps of the ballast: held until a collection runs with it, then a GOGC of its own until the
// next collection, then gcPercent.
const (
	ballastDone = iota
	ballastHeld
	ballastPaced
)

var (
	ballast      []byte
	ballastStep  atomic.Int32
	ballastMutex sync.Mutex
	// ballastCycles is how many collections had run when the step started.
	ballastCycles uint64
	requests      atomic.Uint64
)

func init() {
	// The rows are copied to C as they are.
	if unsafe.Sizeof(parser.VeslintRow{}) != C.sizeof_veslint_tsgo_row {
		panic("veslint_tsgo: parser.VeslintRow and veslint_tsgo_row have different layouts")
	}
	if os.Getenv("GOGC") != "" {
		return
	}
	debug.SetGCPercent(gcPercent)
	if os.Getenv("GOMEMLIMIT") != "" {
		return
	}
	ballast = make([]byte, gcBallast)
	// Allocating the ballast starts a collection (the heap goal starts at 8 MiB): it ends here, so
	// that the next one is the first with the heap of a lint.
	runtime.GC()
	ballastCycles = gcCycles()
	ballastStep.Store(ballastHeld)
}

// gcCycles is how many collections have run.
func gcCycles() uint64 {
	samples := []metrics.Sample{{Name: "/gc/cycles/total:gc-cycles"}}
	metrics.Read(samples)
	if samples[0].Value.Kind() != metrics.KindUint64 {
		return 0
	}
	return samples[0].Value.Uint64()
}

// release_ballast takes the next step of the ballast once a collection has run since the last.
func release_ballast() {
	if ballastStep.Load() == ballastDone || requests.Add(1)%64 != 0 {
		return
	}
	ballastMutex.Lock()
	defer ballastMutex.Unlock()
	cycles := gcCycles()
	if cycles == ballastCycles {
		return
	}
	switch ballastStep.Load() {
	case ballastHeld:
		ballast = nil
		// The heap the collection kept counts the ballast: the goal of the next collection is
		// that heap times 1 + GOGC/100, which this GOGC makes (the heap without the ballast)
		// times 1 + gcPercent/100.
		samples := []metrics.Sample{{Name: "/gc/heap/live:bytes"}}
		metrics.Read(samples)
		percent := gcPercent
		if samples[0].Value.Kind() == metrics.KindUint64 && samples[0].Value.Uint64() > 0 {
			live := int64(samples[0].Value.Uint64())
			kept := max(live-gcBallast, live/8)
			percent = max(int(kept*(100+gcPercent)/live)-100, 10)
		}
		debug.SetGCPercent(percent)
		ballastCycles = gcCycles()
		ballastStep.Store(ballastPaced)
	case ballastPaced:
		debug.SetGCPercent(gcPercent)
		ballastStep.Store(ballastDone)
	}
}

func main() {}
