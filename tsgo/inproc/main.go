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
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"unsafe"

	"github.com/microsoft/TypeScript/tsc/internal/api"
	"github.com/microsoft/TypeScript/tsc/internal/ast"
	"github.com/microsoft/TypeScript/tsc/internal/compiler"
	"github.com/microsoft/TypeScript/tsc/internal/locale"
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
	name := goString(method, methodLen)
	if name == "createSnapshot" || name == "updateSnapshot" {
		armBallast.Do(arm_ballast)
	}
	release_ballast()
	p := session(handle)
	if p == nil {
		cBytes([]byte("the TypeScript session is closed"), out, outLen)
		return 0
	}
	buffer := answerBuffers.Get().(*[]byte)
	messageType, answer := p.Request(int(worker), name, goBytes(payload, payloadLen), (*buffer)[:0])
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

// cConverter is a converter that writes its rows in C memory, which veslint takes as it is: the
// rows of a file are not copied out of a buffer of Go's, and no converter keeps a buffer the size
// of the largest file it converted (Go's collector counted it as live in every converter of the
// pool: tens of megabytes for the largest files of the TypeScript compiler). Without types, median
// of 5 alternated runs on the TypeScript compiler: peak memory 538 -> 371 MB (361 -> 233 MB with
// VESLINT_CPUS=1), the same time.
type cConverter struct {
	*parser.VeslintConverter
	// The C buffer of the rows of the file being converted, nil between files.
	buffer unsafe.Pointer
}

func newCConverter(l *parser.VeslintLanguage) *cConverter {
	c := &cConverter{VeslintConverter: parser.NewVeslintConverter(l)}
	c.Grow = c.grow
	return c
}

func (c *cConverter) grow(rows []parser.VeslintRow, need int) []parser.VeslintRow {
	if rows == nil {
		// A new file: a buffer left by a conversion that did not finish is freed.
		c.free()
	}
	room := max(need, cap(rows)+cap(rows)/2)
	p := C.realloc(c.buffer, C.size_t(room)*C.size_t(unsafe.Sizeof(parser.VeslintRow{})))
	if p == nil {
		panic("veslint_tsgo: out of memory for the rows")
	}
	c.buffer = p
	return unsafe.Slice((*parser.VeslintRow)(p), room)[:len(rows)]
}

// take hands the buffer of `count` rows over to the caller, without the room left at its end.
func (c *cConverter) take(count int) unsafe.Pointer {
	p := c.buffer
	c.buffer = nil
	if p == nil {
		return C.malloc(1)
	}
	if q := C.realloc(p, C.size_t(max(count, 1))*C.size_t(unsafe.Sizeof(parser.VeslintRow{}))); q != nil {
		p = q
	}
	return p
}

func (c *cConverter) free() {
	if c.buffer != nil {
		C.free(c.buffer)
		c.buffer = nil
	}
}

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
	convertDiagnostics = 1 // TypeScript reports parse diagnostics (ESLint's "Parsing error"): no rows, the diagnostics
	convertFailed      = 2 // the converter failed: no rows (the caller parses with tree-sitter)
	convertNoLanguage  = 3 // veslint_tsgo_convert_language was not called for the language
)

// veslint_tsgo_convert parses `text` with TypeScript's parser and writes the rows of
// tree-sitter's tree of it: one call per file. `flags` is 1 for TSX, plus 2 for ESLint's
// sourceType "script". On convertRows, *rows is a malloc'd array of *count veslint_tsgo_row in
// preorder; on convertDiagnostics, it is the parse diagnostics as text of *count bytes (see
// diagnosticsText). The caller frees either with veslint_tsgo_free; otherwise *rows is NULL.
//
//export veslint_tsgo_convert
func veslint_tsgo_convert(flags C.int, text *C.char, textLen C.size_t, rows **C.veslint_tsgo_row, count *C.size_t) C.int {
	return convert(flags, text, textLen, nil, rows, count)
}

// veslint_tsgo_convert_file is veslint_tsgo_convert for a file of a program of the session
// `handle`: it converts the program's AST of the file when it is the one to convert
// (VeslintConverter.ConvertFile: with flag 4, the AST typescript-eslint lints with `projectService`
// or `project`, whenever it is a parse of `text`; otherwise when it is the one a parse of `text`
// gives), and parses `text` otherwise. `params` name the snapshot, the
// project and the file as the parameters of veslint/nodesAtRanges, without values
// (InProcess.VeslintSourceFile). In a lint with types the program has parsed every file already:
// parsing it again was about 5 % of a lint of the TypeScript compiler, and its AST was garbage that
// brought Go's next collection closer and raised the peak (with no-floating-promises, the
// TypeScript compiler 784 -> 648 MB and 2.59 -> 2.23 s, median of 3 alternated runs).
//
//export veslint_tsgo_convert_file
func veslint_tsgo_convert_file(handle C.longlong, params *C.char, paramsLen C.size_t, flags C.int, text *C.char, textLen C.size_t, rows **C.veslint_tsgo_row, count *C.size_t) C.int {
	var file *ast.SourceFile
	if p := session(handle); p != nil {
		file = p.VeslintSourceFile(unsafe.Slice((*byte)(unsafe.Pointer(params)), int(paramsLen)))
	}
	return convert(flags, text, textLen, file, rows, count)
}

// checkProgramAST (VESLINT_CHECK_PROGRAM_AST=1) converts the text of every file whose program's
// AST was converted too, and writes on stderr `veslint_tsgo: checked <path>` for each, or where the
// rows or diagnostics differ (the text's are then the ones given).
var checkProgramAST = os.Getenv("VESLINT_CHECK_PROGRAM_AST") == "1"

// convert is veslint_tsgo_convert, of the program's AST `file` when it may be converted.
func convert(flags C.int, text *C.char, textLen C.size_t, file *ast.SourceFile, rows **C.veslint_tsgo_row, count *C.size_t) (result C.int) {
	*rows = nil
	*count = 0
	tsx := flags & 1
	l := convertLanguages[tsx].Load()
	if l == nil {
		return convertNoLanguage
	}
	c, _ := converters[tsx].Get().(*cConverter)
	if c == nil {
		c = newCConverter(l)
	}
	c.Script = flags&2 != 0
	defer func() {
		// A converter that panicked may hold any state: it is not reused.
		if r := recover(); r != nil {
			c.free()
			*rows = nil
			*count = 0
			result = convertFailed
			return
		}
		converters[tsx].Put(c)
	}()
	// The text is not copied: the call is synchronous, and the converter keeps nothing of the file
	// once it returns (VeslintConverter.forget); the parser in TypeScript's pool keeps its scanner,
	// which keeps the text but reads it again only after it is given the next one.
	var source string
	if textLen > 0 {
		source = unsafe.String((*byte)(unsafe.Pointer(text)), int(textLen))
	}
	var out []parser.VeslintRow
	var diagnostics []*ast.Diagnostic
	fromProgram := false
	if file != nil {
		out, diagnostics, fromProgram = c.ConvertFile(file, source, flags&4 != 0)
	}
	if !fromProgram {
		out, diagnostics = c.Convert(source)
	} else if checkProgramAST {
		// The text parsed as the program parsed it: a module or a script.
		script := file.ExternalModuleIndicator == nil
		if want, wantDiagnostics, same := checkConverted(l, script, file.FileName().AsString(), source, out, diagnostics); !same {
			// The rows of the text, copied below.
			c.free()
			out, diagnostics = want, wantDiagnostics
		}
	}
	if len(diagnostics) > 0 {
		c.free()
		report := diagnosticsText(diagnostics)
		p := C.malloc(C.size_t(max(len(report), 1)))
		if p == nil {
			return convertFailed
		}
		C.memcpy(p, unsafe.Pointer(unsafe.StringData(report)), C.size_t(len(report)))
		*rows = (*C.veslint_tsgo_row)(p)
		*count = C.size_t(len(report))
		return convertDiagnostics
	}
	if c.buffer == nil {
		// The rows of the text that checkConverted gave instead of the program's: a copy.
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
	*rows = (*C.veslint_tsgo_row)(c.take(len(out)))
	*count = C.size_t(len(out))
	return convertRows
}

// checkConverted compares the rows and diagnostics of a program's AST (`rows` and `diagnostics`)
// with those of a parse of `text` (as a script when `script`), which it returns, and tells whether
// they are the same.
func checkConverted(l *parser.VeslintLanguage, script bool, name string, text string, rows []parser.VeslintRow, diagnostics []*ast.Diagnostic) ([]parser.VeslintRow, []*ast.Diagnostic, bool) {
	fresh := parser.NewVeslintConverter(l)
	fresh.Script = script
	want, wantDiagnostics := fresh.Convert(text)
	problem := ""
	if got, expected := diagnosticsText(diagnostics), diagnosticsText(wantDiagnostics); got != expected {
		problem = "the diagnostics of the program's AST differ from those of a parse of the text"
	} else if len(rows) != len(want) {
		problem = "the program's AST has " + strconv.Itoa(len(rows)) + " rows, a parse of the text " + strconv.Itoa(len(want))
	} else {
		for i := range rows {
			if rows[i] != want[i] {
				problem = "row " + strconv.Itoa(i) + " of the program's AST differs from that of a parse of the text"
				break
			}
		}
	}
	if problem != "" {
		os.Stderr.WriteString("veslint_tsgo: " + name + ": " + problem + "\n")
	} else {
		os.Stderr.WriteString("veslint_tsgo: checked " + name + "\n")
	}
	return want, wantDiagnostics, problem == ""
}

// diagnosticsText writes parse diagnostics as transpileModule's response gives them (the first is
// ESLint's "Parsing error"): in the order of the program's syntactic diagnostics (by position,
// SortAndDeduplicateDiagnostics), each as `code pos length` on a line, `pos` in UTF-16 units from
// the start of the text, then its message of `length` bytes as the API localizes it.
func diagnosticsText(diagnostics []*ast.Diagnostic) string {
	var b strings.Builder
	for _, d := range compiler.SortAndDeduplicateDiagnostics(diagnostics) {
		pos := d.Pos()
		if file := d.File(); file != nil {
			pos = file.GetPositionMap().UTF8ToUTF16(max(0, min(pos, len(file.Text()))))
		}
		message := d.Localize(locale.Default)
		b.WriteString(strconv.Itoa(int(d.Code())))
		b.WriteByte(' ')
		b.WriteString(strconv.Itoa(pos))
		b.WriteByte(' ')
		b.WriteString(strconv.Itoa(len(message)))
		b.WriteByte('\n')
		b.WriteString(message)
	}
	return b.String()
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
//
// The ballast is taken by the first createSnapshot or updateSnapshot request (arm_ballast), which
// build programs, not when the process starts: a lint without types builds none, and there Go only
// parses (the converter), whose garbage is all short-lived. With the ballast from the start, that
// garbage stayed in memory until the heap reached three times the ballast: on the TypeScript
// compiler without types, one collection in the whole lint, at 386 MB. Taken later, median of 5
// alternated runs: peak memory 469 -> 371 MB (338 -> 233 MB with VESLINT_CPUS=1), the same time.
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
	armBallast   sync.Once
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
}

// arm_ballast takes the ballast, once, unless the environment sets GOGC or GOMEMLIMIT.
func arm_ballast() {
	if os.Getenv("GOGC") != "" || os.Getenv("GOMEMLIMIT") != "" {
		return
	}
	ballastMutex.Lock()
	defer ballastMutex.Unlock()
	ballast = make([]byte, gcBallast)
	// Allocating the ballast starts a collection (the heap goal is that of the small heap before
	// it): it ends here, so that the next one is the first with the heap of the programs.
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
