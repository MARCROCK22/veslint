module rules

import estree
import offsets

// Helpers of lib/utils (eslint-plugin-vue 10.12.1) for the script rules of the VR6 batch (prefix
// `vx6_`), which the shared vue_*.v files do not have.

// vx6_line_start_index is the start of the line of `offset` as ESLint's lines break the text
// (`\r\n`, `\n`, `\r`, U+2028 and U+2029).
fn vx6_line_start_index(src string, offset int) int {
	return offsets.line_start_before(src, offset)
}

// vx6_previous_line_end is getIndexFromLoc({line: line - 1, column: lines[line - 2].length}) for
// the line that starts at `line_start` (not the first one): where the line before it ends, before
// its line terminator.
fn vx6_previous_line_end(src string, line_start int) int {
	mut end := line_start
	if end >= 2 && src[end - 1] == `\n` && src[end - 2] == `\r` {
		end -= 2
	} else if end >= 1 && (src[end - 1] == `\n` || src[end - 1] == `\r`) {
		end--
	} else if end >= 3 {
		end -= 3 // U+2028 or U+2029
	}
	return end
}

// vx6_edit_distance ports editDistance: the Levenshtein distance of two strings, in UTF-16 units.
fn vx6_edit_distance(a string, b string) int {
	if a == b {
		return 0
	}
	ua := utf16_units(a)
	ub := utf16_units(b)
	mut dp := [][]int{len: ua.len + 1, init: []int{len: ub.len + 1}}
	for i in 0 .. ua.len + 1 {
		dp[i][0] = i
	}
	for j in 0 .. ub.len + 1 {
		dp[0][j] = j
	}
	for i in 1 .. ua.len + 1 {
		for j in 1 .. ub.len + 1 {
			dp[i][j] = if ua[i - 1] == ub[j - 1] {
				dp[i - 1][j - 1]
			} else {
				vx6_min3(dp[i - 1][j], dp[i][j - 1], dp[i - 1][j - 1]) + 1
			}
		}
	}
	return dp[ua.len][ub.len]
}

fn vx6_min3(a int, b int, c int) int {
	mut m := if a < b { a } else { b }
	return if c < m { c } else { m }
}

// vx6_is_in_range is isInRange of two ESTree nodes: `inner` is inside `outer`.
fn vx6_is_in_range(t &estree.EsTree, outer int, inner int) bool {
	return t.nodes[outer].start <= t.nodes[inner].start && t.nodes[inner].end <= t.nodes[outer].end
}

// vx6_raw is the source text of an ESTree node.
fn (c &Checker) vx6_raw(t &estree.EsTree, node int) string {
	return c.src[t.nodes[node].start..t.nodes[node].end]
}

// vx6_script_setup_imports are the ImportDeclarations of the program inside `<script setup>`
// (the ImportDeclaration listener of defineScriptSetupVisitor), in order.
fn (s &VueScript) vx6_script_setup_imports(t &estree.EsTree) []int {
	mut out := []int{}
	for statement in t.list(t.root, .body) or { []int{} } {
		if t.typ(statement) == .import_declaration && s.in_script_setup(t, statement) {
			out << statement
		}
	}
	return out
}
