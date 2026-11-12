module rules

import offsets
import treesitter { node_end, node_start }

// Fixes and suggestions, like ESLint's RuleFixer. A fixer of typescript-eslint returns one fix or
// several; ESLint merges those of a report into a single one (merge_fixes), and that is what a
// Finding carries. Offsets are bytes of the source without its BOM; the output converts them to
// ESLint's UTF-16 ranges.
//
// The ranges are ESTree's, not tree-sitter's: a parenthesized_expression is not a node in ESTree
// (the range of `(a)` is that of `a`), and a rule that replaces "the node" must use the range the
// original rule uses.

// fix_replace_range ports fixer.replaceTextRange.
fn fix_replace_range(start int, end int, text string) Fix {
	return Fix{
		start: start
		end:   end
		text:  text
	}
}

// fix_replace ports fixer.replaceText for a tree-sitter node whose range is the ESTree node's.
fn fix_replace(n C.TSNode, text string) Fix {
	return fix_replace_range(node_start(n), node_end(n), text)
}

// fix_remove_range ports fixer.removeRange.
fn fix_remove_range(start int, end int) Fix {
	return fix_replace_range(start, end, '')
}

// fix_remove ports fixer.remove.
fn fix_remove(n C.TSNode) Fix {
	return fix_replace(n, '')
}

// fix_insert_before_range ports fixer.insertTextBeforeRange: the text goes at `offset`.
fn fix_insert_at(offset int, text string) Fix {
	return fix_replace_range(offset, offset, text)
}

// fix_insert_before ports fixer.insertTextBefore.
fn fix_insert_before(n C.TSNode, text string) Fix {
	return fix_insert_at(node_start(n), text)
}

// fix_insert_after ports fixer.insertTextAfter.
fn fix_insert_after(n C.TSNode, text string) Fix {
	return fix_insert_at(node_end(n), text)
}

// utf16_column is ESLint's `loc.column` of a byte offset: the UTF-16 units from the start of its
// line (ESLint's lines: `\r\n`, `\n`, a lone `\r`, U+2028 and U+2029 break them).
fn utf16_column(src string, offset int) int {
	line_start := offsets.line_start_before(src, offset)
	mut units := 0
	for i in line_start .. offset {
		b := src[i]
		if (b & 0xC0) != 0x80 {
			units += if b >= 0xF0 { 2 } else { 1 }
		}
	}
	return units
}

// merge_fixes ports ESLint's mergeFixes (lib/linter/report-translator.js): the fixes of one report
// become a single fix from the start of the first to the end of the last, with the source text
// between them kept. They are sorted by start and then by end, keeping the order of the ones with
// the same range; none for no fixes, and an error if
// two overlap ("Fix objects must not be overlapped in a report.", which ESLint throws).
fn (c &Checker) merge_fixes(fixes []Fix) !(bool, Fix) {
	if fixes.len == 0 {
		return false, Fix{}
	}
	if fixes.len == 1 {
		return true, fixes[0]
	}
	// ESLint sorts with a stable sort: fixes with the same range keep the order of the fixer.
	mut order := []int{len: fixes.len, init: index}
	order.sort_with_compare(fn [fixes] (a &int, b &int) int {
		x := fixes[*a]
		y := fixes[*b]
		if x.start != y.start {
			return if x.start < y.start { -1 } else { 1 }
		}
		if x.end != y.end {
			return if x.end < y.end { -1 } else { 1 }
		}
		return *a - *b
	})
	sorted := order.map(fixes[it])
	start := sorted[0].start
	end := sorted[sorted.len - 1].end
	mut text := []u8{}
	mut last := start
	for fix in sorted {
		if fix.start < last {
			return error('fix objects must not be overlapped in a report')
		}
		text << c.src[last..fix.start].bytes()
		text << fix.text.bytes()
		last = fix.end
	}
	text << c.src[last..end].bytes()
	return true, Fix{
		start: start
		end:   end
		text:  text.bytestr()
	}
}

// apply_fixes ports ESLint's SourceCodeFixer.applyFixes: the source with the fixes of the findings
// applied, in order of range; a fix that starts at or before the end of the previous one is left
// for another pass. `fixed` is false when no finding has a fix.
pub fn apply_fixes(src string, findings []Finding) (bool, string) {
	fixable := findings.filter(it.has_fix)
	if fixable.len == 0 {
		return false, src
	}
	mut order := []int{len: fixable.len, init: index}
	order.sort_with_compare(fn [fixable] (a &int, b &int) int {
		x := fixable[*a].fix
		y := fixable[*b].fix
		if x.start != y.start {
			return if x.start < y.start { -1 } else { 1 }
		}
		if x.end != y.end {
			return if x.end < y.end { -1 } else { 1 }
		}
		return *a - *b
	})
	mut out := []u8{cap: src.len}
	mut last := -1 // the end of the last fix applied; -1 before the first one
	for index in order {
		fix := fixable[index].fix
		if last >= fix.start || fix.start > fix.end {
			continue
		}
		out << src[if last < 0 { 0 } else { last }..fix.start].bytes()
		out << fix.text.bytes()
		last = fix.end
	}
	out << src[if last < 0 { 0 } else { last }..].bytes()
	return true, out.bytestr()
}

// with_fixes returns the finding with the fixes of its fixer merged; without fixes it is the same
// finding (a fixer that returns null or an empty array).
fn (c &Checker) with_fixes(f Finding, fixes []Fix) !Finding {
	has_fix, fix := c.merge_fixes(fixes)!
	return Finding{
		...f
		has_fix: has_fix
		fix:     fix
	}
}

// suggestion builds a suggestion from the fixes of its fixer; `ok` is false when the fixer returns
// null or no fixes, and ESLint drops the suggestion.
fn (c &Checker) suggestion(message_id string, data map[string]string, fixes []Fix) !(bool, Suggestion) {
	has_fix, fix := c.merge_fixes(fixes)!
	return has_fix, Suggestion{
		message_id: message_id
		data:       data
		fix:        fix
	}
}
