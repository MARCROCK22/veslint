// veslint's converter from TypeScript's AST to tree-sitter's tree. tsgo/inproc/build.sh adds this
// file to TypeScript's internal/parser with an overlay (as veslint_convert.go), so it builds with
// the parser of the commit veslint links.
//
// veslint's rules read the tree of its tree-sitter grammar (patched tree-sitter-typescript) as flat
// rows in preorder. The converter parses a file with TypeScript's parser and writes exactly the rows
// tree-sitter's parse gives: the same visible nodes in the same order, each with tree-sitter's
// symbol and field id (looked up by name in the grammar's tables, never hard-coded), its named and
// extra flags, its byte range, its points and its place in the tree. What the AST has no node for
// (punctuation, keywords, the pieces of strings and templates) is scanned again with TypeScript's
// scanner from the text between the children, and the comments become extras where tree-sitter's
// parser puts them: in the innermost node that has tokens before and after the comment.
//
// Only files TypeScript parses without diagnostics need the same tree: the others get ESLint's
// "Parsing error" and nothing else, so for them Convert only says so (and does not crash).
package parser

import (
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/microsoft/TypeScript/tsc/internal/ast"
	"github.com/microsoft/TypeScript/tsc/internal/core"
	"github.com/microsoft/TypeScript/tsc/internal/scanner"
	"github.com/microsoft/TypeScript/tsc/internal/tspath"
)

// The flags of a row (tree-sitter's ts_node_is_named, is_extra, is_missing, is_error, has_error).
const (
	VeslintNamed    = 1
	VeslintExtra    = 2
	VeslintMissing  = 4
	VeslintError    = 8
	VeslintHasError = 16
	// VeslintNone is the parent of the root and the next sibling of a last child.
	VeslintNone = ^uint32(0)
)

// VeslintRow is one node of tree-sitter's tree: its values as tree-sitter's API gives them
// (ts_node_symbol, ts_tree_cursor_current_field_id, the flags, ts_node_start_byte/end_byte,
// ts_node_start_point/end_point with columns in bytes) and its place in the preorder: the rows of
// its parent, its next sibling and the last node of its subtree (itself for a leaf).
type VeslintRow struct {
	StartByte, EndByte    uint32
	StartRow, StartColumn uint32
	EndRow, EndColumn     uint32
	Parent, Next, Last    uint32
	Symbol, Field         uint16
	Flags                 uint8
}

// The symbols and fields the converter writes are named once here (namedSymbol, anonymousSymbol,
// field) and resolved in each language's tables by NewVeslintLanguage.
type symbolRef uint16
type fieldRef uint16

var (
	namedNames     []string
	anonymousNames []string
	fieldNames     []string
)

func namedSymbol(name string) symbolRef {
	namedNames = append(namedNames, name)
	return symbolRef(len(namedNames) - 1)
}

func anonymousSymbol(name string) symbolRef {
	anonymousNames = append(anonymousNames, name)
	return symbolRef(len(anonymousNames) - 1)
}

func field(name string) fieldRef {
	fieldNames = append(fieldNames, name)
	return fieldRef(len(fieldNames))
}

// VeslintLanguage holds the symbols and fields of one of the grammar's two languages (TypeScript,
// TSX) the converter uses.
type VeslintLanguage struct {
	tsx       bool
	named     []uint16
	anonymous []uint16
	fields    []uint16
	// The anonymous symbol of each token kind of TypeScript's scanner (its text), 0 for none.
	tokens [ast.KindCount]uint16
	// The quotes of strings and the `${` of templates, which TypeScript's scanner has no token for.
	doubleQuote, singleQuote, dollarBrace uint16
	// unknown is the symbol written for what the converter does not handle (it never matches).
	unknown uint16
}

// NewVeslintLanguage resolves the converter's symbols and fields in a language: symbol gives
// ts_language_symbol_for_name(name, named), field ts_language_field_id_for_name(name).
func NewVeslintLanguage(tsx bool, symbol func(name string, named bool) uint16, fieldID func(name string) uint16) *VeslintLanguage {
	l := &VeslintLanguage{tsx: tsx, unknown: 0xFFFE}
	l.named = make([]uint16, len(namedNames))
	for i, name := range namedNames {
		l.named[i] = symbol(name, true)
	}
	l.anonymous = make([]uint16, len(anonymousNames))
	for i, name := range anonymousNames {
		l.anonymous[i] = symbol(name, false)
	}
	l.fields = make([]uint16, len(fieldNames)+1)
	for i, name := range fieldNames {
		l.fields[i+1] = fieldID(name)
	}
	l.doubleQuote = symbol("\"", false)
	l.singleQuote = symbol("'", false)
	l.dollarBrace = symbol("${", false)
	for kind := ast.KindUnknown; kind < ast.KindCount; kind++ {
		if text := scanner.TokenToString(kind); text != "" {
			l.tokens[kind] = symbol(text, false)
		}
	}
	return l
}

func (l *VeslintLanguage) quote(q string) uint16 {
	if q == "'" {
		return l.singleQuote
	}
	return l.doubleQuote
}

type frame struct {
	index  uint32 // the row of the open node
	prev   uint32 // its last child so far
	cursor int    // where the text it has not written yet starts
}

// VeslintConverter converts files of one language; it keeps its buffers between files and is used
// by one thread at a time.
type VeslintConverter struct {
	l     *VeslintLanguage
	text  string
	file  *ast.SourceFile
	rows  []VeslintRow
	stack []frame
	sc    *scanner.Scanner
	lines []uint32
}

func NewVeslintConverter(l *VeslintLanguage) *VeslintConverter {
	c := &VeslintConverter{l: l, sc: scanner.NewScanner()}
	c.sc.SetSkipTrivia(false)
	return c
}

func (c *VeslintConverter) parse(text string) *ast.SourceFile {
	kind := core.ScriptKindTS
	name := "/veslint.ts"
	if c.l.tsx {
		kind = core.ScriptKindTSX
		name = "/veslint.tsx"
	}
	path := tspath.RootedFilePathFromNormalized(name)
	return ParseSourceFile(ast.SourceFileParseOptions{
		FileName: path,
		PathKey:  tspath.CaseSensitive.PathKey(tspath.RootedPath(path)),
	}, text, kind)
}

// Convert parses `text` (without its BOM, as veslint gives tree-sitter) and returns its rows, or
// diagnostics = true when TypeScript reports parse diagnostics (the rows are then not meaningful).
// The rows are the converter's buffer, valid until its next call.
func (c *VeslintConverter) Convert(text string) (rows []VeslintRow, diagnostics bool) {
	file := c.parse(text)
	if len(file.Diagnostics()) > 0 {
		return nil, true
	}
	c.convert(file)
	return c.rows, false
}

// Diagnostics lists the parse diagnostics of `text` (code@position), for the differential test.
func (c *VeslintConverter) Diagnostics(text string) []string {
	var out []string
	for _, d := range c.parse(text).Diagnostics() {
		out = append(out, fmt.Sprintf("%d@%d %s", d.Code(), d.Pos(), d.String()))
	}
	return out
}

// ConvertTimed is Convert's two halves, timed (the benchmark of tests/tsconv).
func (c *VeslintConverter) ConvertTimed(text string) (parse, conversion time.Duration) {
	t0 := time.Now()
	file := c.parse(text)
	t1 := time.Now()
	if len(file.Diagnostics()) == 0 {
		c.convert(file)
	}
	return t1.Sub(t0), time.Since(t1)
}

func (c *VeslintConverter) convert(file *ast.SourceFile) {
	c.file = file
	c.text = file.Text()
	c.rows = c.rows[:0]
	c.stack = c.stack[:0]
	c.sc.SetText(c.text)
	c.sc.SetLanguageVariant(file.LanguageVariant)
	c.program(file)
	c.points()
}

func (c *VeslintConverter) named(s symbolRef) uint16     { return c.l.named[s] }
func (c *VeslintConverter) anonymous(s symbolRef) uint16 { return c.l.anonymous[s] }
func (c *VeslintConverter) field(f fieldRef) uint16      { return c.l.fields[f] }

// push appends a row under the innermost open node.
func (c *VeslintConverter) push(symbol, field uint16, flags uint8, start, end int) uint32 {
	index := uint32(len(c.rows))
	parent := VeslintNone
	if depth := len(c.stack); depth > 0 {
		top := &c.stack[depth-1]
		parent = top.index
		if top.prev != VeslintNone {
			c.rows[top.prev].Next = index
		}
		top.prev = index
	}
	c.rows = append(c.rows, VeslintRow{StartByte: uint32(start), EndByte: uint32(end), Parent: parent, Next: VeslintNone, Last: index, Symbol: symbol, Field: field, Flags: flags})
	return index
}

func (c *VeslintConverter) top() *frame { return &c.stack[len(c.stack)-1] }

// flush writes the tokens and comments of the text from the cursor to `to` under the innermost
// open node: the tokens as anonymous rows named by their text, the comments as extras.
func (c *VeslintConverter) flush(to int) {
	if len(c.stack) == 0 {
		return
	}
	t := c.top()
	if t.cursor >= to {
		return
	}
	c.sc.ResetTokenState(t.cursor)
	for {
		kind := c.sc.Scan()
		start := c.sc.TokenStart()
		if kind == ast.KindEndOfFile || start >= to {
			break
		}
		end := c.sc.TokenEnd()
		switch kind {
		case ast.KindWhitespaceTrivia, ast.KindNewLineTrivia:
		case ast.KindSingleLineCommentTrivia, ast.KindMultiLineCommentTrivia:
			c.push(c.named(sComment), 0, VeslintNamed|VeslintExtra, start, end)
		default:
			symbol := c.l.tokens[kind]
			if symbol == 0 {
				symbol = c.l.unknown
			}
			c.push(symbol, 0, 0, start, end)
		}
	}
	c.top().cursor = to
}

// open starts a node at `start` under the innermost open node.
func (c *VeslintConverter) open(symbol, field uint16, start int) {
	c.flush(start)
	index := c.push(symbol, field, VeslintNamed, start, start)
	c.stack = append(c.stack, frame{index: index, prev: VeslintNone, cursor: start})
}

// close ends the innermost open node at `end`, writing the tokens and comments before it.
func (c *VeslintConverter) close(end int) {
	c.flush(end)
	t := c.top()
	// A child may end after the AST's end: the comments a block or an automatic semicolon
	// takes.
	if t.prev != VeslintNone && int(c.rows[t.prev].EndByte) > end {
		end = int(c.rows[t.prev].EndByte)
	}
	row := &c.rows[t.index]
	row.EndByte = uint32(end)
	row.Last = uint32(len(c.rows) - 1)
	c.stack = c.stack[:len(c.stack)-1]
	if len(c.stack) > 0 {
		if p := c.top(); p.cursor < end {
			p.cursor = end
		}
	}
}

// leaf writes a node without children.
func (c *VeslintConverter) leaf(symbol, field uint16, flags uint8, start, end int) {
	c.flush(start)
	c.push(symbol, field, flags, start, end)
	c.top().cursor = end
}

// peek scans the next token after the cursor (comments and whitespace skipped).
func (c *VeslintConverter) peek() (kind ast.Kind, start, end int) {
	c.sc.ResetTokenState(c.top().cursor)
	for {
		kind = c.sc.Scan()
		switch kind {
		case ast.KindWhitespaceTrivia, ast.KindNewLineTrivia, ast.KindSingleLineCommentTrivia, ast.KindMultiLineCommentTrivia:
			continue
		}
		return kind, c.sc.TokenStart(), c.sc.TokenEnd()
	}
}

// tok writes the next token as an anonymous row with `field`, and returns its kind.
func (c *VeslintConverter) tok(field uint16) ast.Kind {
	kind, start, end := c.peek()
	symbol := c.l.tokens[kind]
	if symbol == 0 {
		symbol = c.l.unknown
	}
	c.leaf(symbol, field, 0, start, end)
	return kind
}

// tokAs writes the next token as a row of `symbol`.
func (c *VeslintConverter) tokAs(symbol, field uint16, flags uint8) {
	_, start, end := c.peek()
	c.leaf(symbol, field, flags, start, end)
}

// tokNode writes a token node of the AST (a keyword, an operator) as an anonymous row.
func (c *VeslintConverter) tokNode(n *ast.Node, field uint16) {
	symbol := c.l.tokens[n.Kind]
	if symbol == 0 {
		symbol = c.l.unknown
	}
	c.leaf(symbol, field, 0, c.start(n), n.End())
}

// openNext starts a node at the next token.
func (c *VeslintConverter) openNext(symbol, field uint16) {
	_, start, _ := c.peek()
	c.open(symbol, field, start)
}

// closeAfter writes the tokens up to the next one of `kind`, that one included, and ends the
// innermost open node after it (the `)` of formal_parameters, the `}` of a body).
func (c *VeslintConverter) closeAfter(kind ast.Kind) {
	for {
		k, _, end := c.peek()
		if k == ast.KindEndOfFile {
			break
		}
		c.tok(0)
		if k == kind {
			c.close(end)
			return
		}
	}
	c.closeHere()
}

// absorbComments writes the comments tree-sitter keeps at the end of a node that ends with an
// automatic semicolon or with the optional one after a block's `}`: its external scanner puts
// that zero-width token after the comments on the line of the last token (a line comment, block
// comments), when the line ends after them, or a `}` or the end of the file follows; a block
// comment with a line break followed by more on its line ends the statement before it.
func (c *VeslintConverter) absorbComments() {
	t := c.top()
	p := t.cursor
	var comments [][2]int
	commit := func() {
		for _, cm := range comments {
			c.push(c.named(sComment), 0, VeslintNamed|VeslintExtra, cm[0], cm[1])
			c.top().cursor = cm[1]
		}
	}
	for {
		i := c.skipInlineSpace(p)
		if i >= len(c.text) || c.text[i] == '}' || c.isLineBreak(i) {
			commit()
			return
		}
		if c.text[i] != '/' || i+1 >= len(c.text) {
			return
		}
		switch c.text[i+1] {
		case '/':
			end := i + 2
			for end < len(c.text) && !c.isLineBreak(end) {
				end++
			}
			comments = append(comments, [2]int{i, end})
			p = end
		case '*':
			close := strings.Index(c.text[i+2:], "*/")
			if close < 0 {
				return
			}
			end := i + 2 + close + 2
			if c.hasLineBreak(i, end) {
				j := c.skipInlineSpace(end)
				if !(j >= len(c.text) || c.text[j] == '}' || c.isLineBreak(j)) {
					commit()
					return
				}
			}
			comments = append(comments, [2]int{i, end})
			p = end
		default:
			return
		}
	}
}

// skipInlineSpace skips the white space that is not a line break, as the scanner's
// is_inline_space does.
func (c *VeslintConverter) skipInlineSpace(i int) int {
	for i < len(c.text) {
		ch := c.text[i]
		if ch == ' ' || ch == '\t' || ch == 0x0B || ch == 0x0C {
			i++
			continue
		}
		if ch < 0x80 {
			return i
		}
		r, size := utf8.DecodeRuneInString(c.text[i:])
		if r == 0x85 || r == 0xA0 || r == 0x1680 || (r >= 0x2000 && r <= 0x200B) || r == 0x202F || r == 0x205F || r == 0x2060 || r == 0x3000 || r == 0xFEFF {
			i += size
			continue
		}
		return i
	}
	return i
}

func (c *VeslintConverter) isLineBreak(i int) bool {
	switch c.text[i] {
	case '\n', '\r':
		return true
	case 0xE2:
		return strings.HasPrefix(c.text[i:], "\u2028") || strings.HasPrefix(c.text[i:], "\u2029")
	}
	return false
}

func (c *VeslintConverter) hasLineBreak(from, to int) bool {
	for i := from; i < to; i++ {
		if c.isLineBreak(i) {
			return true
		}
	}
	return false
}

// lastIsSemicolon tells whether the last row written under the innermost open node is a `;`.
func (c *VeslintConverter) lastIsSemicolon() bool {
	p := c.top().prev
	return p != VeslintNone && c.rows[p].Symbol == c.l.tokens[ast.KindSemicolonToken] && c.rows[p].Flags&VeslintNamed == 0
}

// closeStatement ends a statement whose grammar rule ends with `_semicolon`: after its `;`, or
// after the comments its automatic semicolon takes.
func (c *VeslintConverter) closeStatement(end int) {
	c.flush(end)
	if !c.lastIsSemicolon() {
		c.absorbComments()
	}
	c.closeHere()
}

// closeHere ends the innermost open node after what it has written: the tokens after it (a `;`
// TypeScript keeps in the node) are its parent's.
func (c *VeslintConverter) closeHere() {
	t := c.top()
	end := int(c.rows[t.index].StartByte)
	if t.prev != VeslintNone {
		end = int(c.rows[t.prev].EndByte)
	}
	t.cursor = end
	c.close(end)
}

// start is where a node's first token starts (its Pos is where its leading trivia start).
func (c *VeslintConverter) start(n *ast.Node) int {
	return scanner.SkipTrivia(c.text, n.Pos())
}

// points fills the rows' points from their bytes: tree-sitter counts rows at '\n' only and
// columns in bytes.
func (c *VeslintConverter) points() {
	c.lines = c.lines[:0]
	c.lines = append(c.lines, 0)
	for i := 0; i < len(c.text); i++ {
		if c.text[i] == '\n' {
			c.lines = append(c.lines, uint32(i+1))
		}
	}
	line := 0
	for i := range c.rows {
		r := &c.rows[i]
		// The starts never decrease in preorder.
		for line+1 < len(c.lines) && c.lines[line+1] <= r.StartByte {
			line++
		}
		for line > 0 && c.lines[line] > r.StartByte {
			line--
		}
		r.StartRow, r.StartColumn = uint32(line), r.StartByte-c.lines[line]
		end := line
		for end+1 < len(c.lines) && c.lines[end+1] <= r.EndByte {
			end++
		}
		r.EndRow, r.EndColumn = uint32(end), r.EndByte-c.lines[end]
	}
}

var (
	sProgram      = namedSymbol("program")
	sComment      = namedSymbol("comment")
	sHashBangLine = namedSymbol("hash_bang_line")
)

func (c *VeslintConverter) program(file *ast.SourceFile) {
	// The root starts at its first token or comment (or at the end of a blank file) and ends at
	// the end of the text.
	start := len(c.text)
	c.sc.ResetTokenState(0)
	for {
		kind := c.sc.Scan()
		if kind == ast.KindWhitespaceTrivia || kind == ast.KindNewLineTrivia {
			continue
		}
		if kind != ast.KindEndOfFile || c.sc.TokenStart() < len(c.text) {
			start = c.sc.TokenStart()
		}
		break
	}
	if scanner.GetShebang(c.text) != "" {
		start = 0
	}
	c.open(c.named(sProgram), 0, start)
	// The scanner skips a shebang as trivia; tree-sitter has a node for it.
	if shebang := scanner.GetShebang(c.text); shebang != "" {
		c.leaf(c.named(sHashBangLine), 0, VeslintNamed, 0, len(shebang))
	}
	for _, s := range file.Statements.Nodes {
		c.statement(s, 0)
	}
	c.close(len(c.text))
}

// generic is the fallback for what the converter does not handle yet: TypeScript's own shape
// under the unknown symbol.
func (c *VeslintConverter) generic(n *ast.Node, field uint16) {
	start := c.start(n)
	if ast.IsTokenKind(n.Kind) || n.Kind == ast.KindIdentifier {
		c.leaf(c.l.unknown, field, VeslintNamed, start, n.End())
		return
	}
	c.open(c.l.unknown, field, start)
	n.ForEachChild(func(child *ast.Node) bool {
		c.expression(child, 0)
		return false
	})
	c.close(n.End())
}
