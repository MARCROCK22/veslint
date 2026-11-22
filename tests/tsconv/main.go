// Command tsconv is the differential test of the converter from TypeScript's AST to tree-sitter's
// tree (tsgo/inproc/convert*.go, in TypeScript's internal/parser through the overlay): it parses
// each file with veslint's tree-sitter grammar and with TypeScript 7.1's parser plus the converter,
// and compares every value of the rows (symbol, field, flags, bytes, points, shape). tests/tsconv/
// build.sh builds it, run.sh runs it on the corpus and sums the results.
//
//	tsconv ts FILE            tree-sitter's rows of FILE
//	tsconv conv FILE          the converter's rows of FILE
//	tsconv diff LIST [i/n]    one line per file of LIST (the i-th of n shards): its result
//	tsconv bench LIST [runs]  timings, one CPU: tree-sitter parse + rows vs TypeScript parse + conversion
package main

/*
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include "tree_sitter/api.h"

const TSLanguage *tree_sitter_typescript(void);
const TSLanguage *tree_sitter_tsx(void);

typedef struct {
	uint32_t start_byte, end_byte;
	uint32_t start_row, start_column, end_row, end_column;
	uint32_t parent, next, prev, last;
	uint16_t symbol, field;
	uint8_t flags;
} tsc_row;

// tsc_rows walks the tree as treesitter/flat_tree.h does (the visible nodes, in preorder, with the
// field the cursor gives each) into `out`, and returns the count, or -1 when `cap` is too small.
static int64_t tsc_rows(TSTree *tree, tsc_row *out, uint32_t cap, uint32_t *open, uint32_t *prev) {
	TSNode root = ts_tree_root_node(tree);
	TSTreeCursor cursor = ts_tree_cursor_new(root);
	uint32_t depth = 0, count = 0;
	for (;;) {
		if (count == cap) {
			ts_tree_cursor_delete(&cursor);
			return -1;
		}
		TSNode node = ts_tree_cursor_current_node(&cursor);
		uint32_t index = count++;
		tsc_row *r = &out[index];
		r->start_byte = ts_node_start_byte(node);
		r->end_byte = ts_node_end_byte(node);
		TSPoint s = ts_node_start_point(node), e = ts_node_end_point(node);
		r->start_row = s.row;
		r->start_column = s.column;
		r->end_row = e.row;
		r->end_column = e.column;
		r->parent = depth == 0 ? UINT32_MAX : open[depth - 1];
		r->next = UINT32_MAX;
		r->prev = UINT32_MAX;
		r->last = index;
		r->symbol = ts_node_symbol(node);
		r->field = depth == 0 ? 0 : ts_tree_cursor_current_field_id(&cursor);
		r->flags = (ts_node_is_named(node) ? 1 : 0) | (ts_node_is_extra(node) ? 2 : 0) |
			(ts_node_is_missing(node) ? 4 : 0) | (ts_node_is_error(node) ? 8 : 0) |
			(ts_node_has_error(node) ? 16 : 0);
		if (depth > 0) {
			if (prev[depth - 1] != UINT32_MAX) {
				out[prev[depth - 1]].next = index;
				r->prev = prev[depth - 1];
			}
			prev[depth - 1] = index;
		}
		if (ts_tree_cursor_goto_first_child(&cursor)) {
			open[depth] = index;
			prev[depth] = UINT32_MAX;
			depth++;
			continue;
		}
		while (!ts_tree_cursor_goto_next_sibling(&cursor)) {
			if (depth == 0 || !ts_tree_cursor_goto_parent(&cursor)) {
				ts_tree_cursor_delete(&cursor);
				return count;
			}
			depth--;
			out[open[depth]].last = count - 1;
		}
	}
}

static uint16_t tsc_symbol(const TSLanguage *lang, const char *name, uint32_t len, bool named) {
	return ts_language_symbol_for_name(lang, name, len, named);
}
*/
import "C"

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"runtime/debug"
	"runtime/pprof"
	"sort"
	"strconv"
	"strings"
	"time"
	"unsafe"

	"github.com/microsoft/TypeScript/tsc/internal/parser"
)

type Row = parser.VeslintRow

// grammar is one of the two languages of veslint's grammar with its converter's tables.
type grammar struct {
	lang   *C.TSLanguage
	parser *C.TSParser
	table  *parser.VeslintLanguage
	names  map[uint16]string // symbol -> name, for the reports
	fields map[uint16]string
}

func newGrammar(tsx bool) *grammar {
	g := &grammar{names: map[uint16]string{}, fields: map[uint16]string{}}
	if tsx {
		g.lang = C.tree_sitter_tsx()
	} else {
		g.lang = C.tree_sitter_typescript()
	}
	g.parser = C.ts_parser_new()
	if !C.ts_parser_set_language(g.parser, g.lang) {
		panic("tree-sitter rejects the grammar")
	}
	symbol := func(name string, named bool) uint16 {
		cs := C.CString(name)
		defer C.free(unsafe.Pointer(cs))
		return uint16(C.tsc_symbol(g.lang, cs, C.uint32_t(len(name)), C.bool(named)))
	}
	field := func(name string) uint16 {
		cs := C.CString(name)
		defer C.free(unsafe.Pointer(cs))
		return uint16(C.ts_language_field_id_for_name(g.lang, cs, C.uint32_t(len(name))))
	}
	g.table = parser.NewVeslintLanguage(tsx, symbol, field)
	for i := 0; i < int(C.ts_language_symbol_count(g.lang)); i++ {
		g.names[uint16(i)] = C.GoString(C.ts_language_symbol_name(g.lang, C.TSSymbol(i)))
	}
	g.names[0xFFFF] = "ERROR"
	for i := 1; i <= int(C.ts_language_field_count(g.lang)); i++ {
		g.fields[uint16(i)] = C.GoString(C.ts_language_field_name_for_id(g.lang, C.TSFieldId(i)))
	}
	return g
}

func (g *grammar) symbolName(s uint16, named bool) string {
	name, ok := g.names[s]
	if !ok {
		return fmt.Sprintf("?%d", s)
	}
	if !named {
		return strconv.Quote(name)
	}
	return name
}

// tsSide parses with tree-sitter and keeps the buffers of the walk.
type tsSide struct {
	rows       []Row
	open, prev []C.uint32_t
}

func (t *tsSide) parse(g *grammar, text string) []Row {
	var ctext *C.char
	if len(text) > 0 {
		ctext = (*C.char)(unsafe.Pointer(unsafe.StringData(text)))
	}
	tree := C.ts_parser_parse_string(g.parser, nil, ctext, C.uint32_t(len(text)))
	defer C.ts_tree_delete(tree)
	n := int(C.ts_node_descendant_count(C.ts_tree_root_node(tree))) + 1
	if cap(t.rows) < n {
		t.rows = make([]Row, n)
		t.open = make([]C.uint32_t, n)
		t.prev = make([]C.uint32_t, n)
	}
	rows := t.rows[:n]
	got := C.tsc_rows(tree, (*C.tsc_row)(unsafe.Pointer(&rows[0])), C.uint32_t(n), &t.open[0], &t.prev[0])
	if got < 0 {
		panic("tsc_rows: more nodes than ts_node_descendant_count")
	}
	return rows[:got]
}

func readSource(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	// veslint strips the BOM before parsing.
	return strings.TrimPrefix(string(data), "\uFEFF")
}

func isTSX(path string) bool { return strings.HasSuffix(path, ".tsx") }

func flagString(f uint8) string {
	var b strings.Builder
	for i, s := range []string{"named", "extra", "missing", "error", "has_error"} {
		if f&(1<<i) != 0 {
			if b.Len() > 0 {
				b.WriteByte(',')
			}
			b.WriteString(s)
		}
	}
	return b.String()
}

func dump(g *grammar, rows []Row, text string) {
	depth := make([]int, len(rows))
	for i, r := range rows {
		if r.Parent != ^uint32(0) && int(r.Parent) < i {
			depth[i] = depth[r.Parent] + 1
		}
		field := ""
		if r.Field != 0 {
			field = g.fields[r.Field] + ": "
		}
		snippet := ""
		if r.EndByte <= uint32(len(text)) && r.StartByte <= r.EndByte {
			snippet = text[r.StartByte:r.EndByte]
			if len(snippet) > 40 {
				snippet = snippet[:40] + "…"
			}
		}
		fmt.Printf("%4d %s%s%s %d-%d (%d,%d)-(%d,%d) [%s] %q\n", i, strings.Repeat("  ", depth[i]), field,
			g.symbolName(r.Symbol, r.Flags&1 != 0), r.StartByte, r.EndByte, r.StartRow, r.StartColumn, r.EndRow,
			r.EndColumn, flagString(r.Flags), snippet)
	}
}

// key identifies a row by its values and its parent's, for the count of identical nodes.
type key struct {
	symbol, field          uint16
	flags                  uint8
	start, end             uint32
	srow, scol, erow, ecol uint32
	psymbol                uint16
	pstart, pend           uint32
}

func keyOf(rows []Row, i int) key {
	r := rows[i]
	k := key{r.Symbol, r.Field, r.Flags, r.StartByte, r.EndByte, r.StartRow, r.StartColumn, r.EndRow, r.EndColumn, 0xFFFF, 0, 0}
	if r.Parent != ^uint32(0) && int(r.Parent) < len(rows) {
		p := rows[r.Parent]
		k.psymbol, k.pstart, k.pend = p.Symbol, p.StartByte, p.EndByte
	}
	return k
}

// compare describes the first difference between the two row sets (empty when they are equal)
// and counts the tree-sitter rows that have an identical row in the converter's (same values,
// same parent), with the kinds of the others.
func compare(g *grammar, want, got []Row, text string) (class string, detail string, same int, missing, extra map[string]int) {
	missing, extra = map[string]int{}, map[string]int{}
	counts := make(map[key]int, len(got))
	for i := range got {
		counts[keyOf(got, i)]++
	}
	for i := range want {
		k := keyOf(want, i)
		if counts[k] > 0 {
			counts[k]--
			same++
		} else {
			missing[g.symbolName(want[i].Symbol, want[i].Flags&1 != 0)]++
		}
	}
	for k, n := range counts {
		if n > 0 {
			extra[g.symbolName(k.symbol, k.flags&1 != 0)] += n
		}
	}
	name := func(rows []Row, i int) string {
		if i < 0 || i >= len(rows) {
			return "-"
		}
		return g.symbolName(rows[i].Symbol, rows[i].Flags&1 != 0)
	}
	parentName := func(rows []Row, i int) string {
		if i < 0 || i >= len(rows) || rows[i].Parent == ^uint32(0) {
			return "-"
		}
		return name(rows, int(rows[i].Parent))
	}
	for i := 0; i < len(want) || i < len(got); i++ {
		if i >= len(want) || i >= len(got) {
			var r Row
			if i < len(got) {
				r = got[i]
				class = fmt.Sprintf("extra row %s in %s", name(got, i), parentName(got, i))
			} else {
				r = want[i]
				class = fmt.Sprintf("missing row %s in %s", name(want, i), parentName(want, i))
			}
			detail = fmt.Sprintf("row %d at %d: %q", i, r.StartByte, clip(text, r.StartByte))
			return
		}
		w, o := want[i], got[i]
		at := fmt.Sprintf("row %d at %d: %q", i, w.StartByte, clip(text, w.StartByte))
		switch {
		case w.Symbol != o.Symbol || w.Flags&3 != o.Flags&3:
			class = fmt.Sprintf("kind in %s: %s, got %s", parentName(want, i), name(want, i), name(got, i))
		case w.StartByte != o.StartByte || w.EndByte != o.EndByte:
			what := "start"
			if w.StartByte == o.StartByte {
				what = "end"
			}
			class = fmt.Sprintf("%s of %s in %s", what, name(want, i), parentName(want, i))
			at += fmt.Sprintf(" (%d-%d, got %d-%d)", w.StartByte, w.EndByte, o.StartByte, o.EndByte)
		case w.Parent != o.Parent:
			class = fmt.Sprintf("parent of %s: %s, got %s", name(want, i), parentName(want, i), parentName(got, i))
		case w.Field != o.Field:
			class = fmt.Sprintf("field of %s in %s: %s, got %s", name(want, i), parentName(want, i), g.fields[w.Field], g.fields[o.Field])
		case w.Flags != o.Flags:
			class = fmt.Sprintf("flags of %s: %s, got %s", name(want, i), flagString(w.Flags), flagString(o.Flags))
		default:
			continue
		}
		detail = at
		return
	}
	// The same nodes: their links and points (a difference there is the converter's own).
	for i := range want {
		w, o := want[i], got[i]
		at := fmt.Sprintf("row %d at %d: %q", i, w.StartByte, clip(text, w.StartByte))
		switch {
		case w.Next != o.Next || w.Prev != o.Prev || w.Last != o.Last:
			class = fmt.Sprintf("shape of %s in %s", name(want, i), parentName(want, i))
		case w.StartRow != o.StartRow || w.StartColumn != o.StartColumn || w.EndRow != o.EndRow || w.EndColumn != o.EndColumn:
			class = fmt.Sprintf("point of %s", name(want, i))
			at += fmt.Sprintf(" ((%d,%d)-(%d,%d), got (%d,%d)-(%d,%d))", w.StartRow, w.StartColumn, w.EndRow, w.EndColumn, o.StartRow, o.StartColumn, o.EndRow, o.EndColumn)
		default:
			continue
		}
		detail = at
		return
	}
	return
}

func clip(text string, at uint32) string {
	if at > uint32(len(text)) {
		return ""
	}
	s := text[at:]
	if len(s) > 30 {
		s = s[:30]
	}
	return s
}

func readList(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		if p := strings.TrimSpace(sc.Text()); p != "" {
			out = append(out, p)
		}
	}
	return out
}

func shard(paths []string, spec string) []string {
	if spec == "" {
		return paths
	}
	parts := strings.Split(spec, "/")
	i, _ := strconv.Atoi(parts[0])
	n, _ := strconv.Atoi(parts[1])
	var out []string
	for j, p := range paths {
		if j%n == i {
			out = append(out, p)
		}
	}
	return out
}

func joinCounts(m map[string]int) string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		if b.Len() > 0 {
			b.WriteByte(' ')
		}
		fmt.Fprintf(&b, "%s=%d", strings.ReplaceAll(k, " ", "_"), m[k])
	}
	return b.String()
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: tsconv ts|conv FILE, tsconv diff LIST [i/n], tsconv bench LIST [runs]")
		os.Exit(2)
	}
	if unsafe.Sizeof(Row{}) != C.sizeof_tsc_row {
		panic("the converter's row and tsc_row have different layouts")
	}
	grammars := [2]*grammar{newGrammar(false), newGrammar(true)}
	pick := func(path string) *grammar {
		if isTSX(path) {
			return grammars[1]
		}
		return grammars[0]
	}
	switch os.Args[1] {
	case "ts":
		text := readSource(os.Args[2])
		var side tsSide
		dump(pick(os.Args[2]), side.parse(pick(os.Args[2]), text), text)
	case "conv":
		text := readSource(os.Args[2])
		g := pick(os.Args[2])
		conv := parser.NewVeslintConverter(g.table)
		rows, diagnostics := conv.Convert(text)
		if diagnostics {
			fmt.Println("# TypeScript reports parse diagnostics:")
			for _, d := range conv.Diagnostics(text) {
				fmt.Println("#  ", d)
			}
		}
		dump(g, rows, text)
	case "diff":
		spec := ""
		if len(os.Args) > 3 {
			spec = os.Args[3]
		}
		convs := [2]*parser.VeslintConverter{parser.NewVeslintConverter(grammars[0].table), parser.NewVeslintConverter(grammars[1].table)}
		var side tsSide
		out := bufio.NewWriter(os.Stdout)
		defer out.Flush()
		for _, path := range shard(readList(os.Args[2]), spec) {
			if _, err := os.Stat(path); err != nil {
				fmt.Fprintf(out, "%s\tmissing\t\t\t0\t0\t\t\n", path)
				continue
			}
			text := readSource(path)
			g := pick(path)
			conv := convs[0]
			if isTSX(path) {
				conv = convs[1]
			}
			want := side.parse(g, text)
			var got []Row
			var diagnostics bool
			var crash string
			func() {
				defer func() {
					if r := recover(); r != nil {
						crash = strings.ReplaceAll(fmt.Sprint(r), "\t", " ")
						for _, line := range strings.Split(string(debug.Stack()), "\n") {
							if strings.Contains(line, "veslint_convert") {
								crash += " @ " + strings.TrimSpace(line)
								break
							}
						}
					}
				}()
				got, diagnostics = conv.Convert(text)
			}()
			tsError := want[0].Flags&16 != 0
			switch {
			case crash != "":
				fmt.Fprintf(out, "%s\tcrash\t%s\t\t%d\t0\t\t\n", path, crash, len(want))
			case diagnostics:
				codes := conv.Diagnostics(text)
				for i, d := range codes {
					codes[i] = d[:strings.IndexByte(d, '@')]
				}
				fmt.Fprintf(out, "%s\tdiagnostics\t%s\t\t%d\t0\t\t\n", path, strings.Join(codes, ","), len(want))
			default:
				class, detail, same, missing, extra := compare(g, want, got, text)
				status := "same"
				if class != "" {
					status = "differ"
					if tsError {
						status = "differ-ts-error"
					}
				}
				fmt.Fprintf(out, "%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\n", path, status, class, strings.ReplaceAll(detail, "\t", " "), len(want), same, joinCounts(missing), joinCounts(extra))
			}
		}
	case "bench":
		runs := 5
		if len(os.Args) > 3 {
			runs, _ = strconv.Atoi(os.Args[3])
		}
		paths := readList(os.Args[2])
		texts := make([]string, len(paths))
		bytes := 0
		for i, p := range paths {
			texts[i] = readSource(p)
			bytes += len(texts[i])
		}
		convs := [2]*parser.VeslintConverter{parser.NewVeslintConverter(grammars[0].table), parser.NewVeslintConverter(grammars[1].table)}
		var side tsSide
		var tsMs, parseMs, convMs []float64
		// TSCONV_PROFILE: a CPU profile of the TypeScript half (parse and conversion) to that file.
		if path := os.Getenv("TSCONV_PROFILE"); path != "" {
			f, err := os.Create(path)
			if err != nil {
				panic(err)
			}
			defer f.Close()
			if err := pprof.StartCPUProfile(f); err != nil {
				panic(err)
			}
			defer pprof.StopCPUProfile()
		}
		for run := 0; run < runs; run++ {
			runtime.GC()
			t0 := time.Now()
			for i, p := range paths {
				side.parse(pick(p), texts[i])
			}
			tsMs = append(tsMs, float64(time.Since(t0).Microseconds())/1000)
			runtime.GC()
			var p, cv time.Duration
			for i, path := range paths {
				conv := convs[0]
				if isTSX(path) {
					conv = convs[1]
				}
				pt, ct := conv.ConvertTimed(texts[i])
				p += pt
				cv += ct
			}
			parseMs = append(parseMs, float64(p.Microseconds())/1000)
			convMs = append(convMs, float64(cv.Microseconds())/1000)
		}
		fmt.Printf("{\"files\":%d,\"bytes\":%d,\"runs\":%d,\"tree_sitter_parse_rows_ms\":%s,\"typescript_parse_ms\":%s,\"conversion_ms\":%s}\n",
			len(paths), bytes, runs, stat(tsMs), stat(parseMs), stat(convMs))
	default:
		fmt.Fprintln(os.Stderr, "unknown mode", os.Args[1])
		os.Exit(2)
	}
}

func stat(v []float64) string {
	s := append([]float64(nil), v...)
	sort.Float64s(s)
	return fmt.Sprintf("{\"min\":%.1f,\"median\":%.1f}", s[0], s[len(s)/2])
}
