module rules

import estree
import offsets
import treesitter

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

// vx6_type_node_types are TYPE_NODE_TYPES of lib/utils/ts-utils/ts-ast.ts (isTypeNode).
const vx6_type_node_types = ['TSAbstractKeyword', 'TSAnyKeyword', 'TSAsyncKeyword', 'TSArrayType',
	'TSBigIntKeyword', 'TSBooleanKeyword', 'TSConditionalType', 'TSConstructorType', 'TSDeclareKeyword',
	'TSExportKeyword', 'TSFunctionType', 'TSImportType', 'TSIndexedAccessType', 'TSInferType',
	'TSIntersectionType', 'TSIntrinsicKeyword', 'TSLiteralType', 'TSMappedType', 'TSNamedTupleMember',
	'TSNeverKeyword', 'TSNullKeyword', 'TSNumberKeyword', 'TSObjectKeyword', 'TSOptionalType',
	'TSQualifiedName', 'TSPrivateKeyword', 'TSProtectedKeyword', 'TSPublicKeyword', 'TSReadonlyKeyword',
	'TSRestType', 'TSStaticKeyword', 'TSStringKeyword', 'TSSymbolKeyword', 'TSTemplateLiteralType',
	'TSThisType', 'TSTupleType', 'TSTypeLiteral', 'TSTypeOperator', 'TSTypePredicate', 'TSTypeQuery',
	'TSTypeReference', 'TSUndefinedKeyword', 'TSUnionType', 'TSUnknownKeyword', 'TSVoidKeyword']

// vx6_is_within_type_node ports isWithinTypeNode: the node or one of its ancestors is a type.
fn vx6_is_within_type_node(t &estree.EsTree, node int) bool {
	mut n := node
	for n >= 0 {
		if t.typ(n).type_name() in vx6_type_node_types {
			return true
		}
		n = t.nodes[n].parent
	}
	return false
}

// vx6_referencing_locally is the Identifier listener of valid-define-props, valid-define-emits
// and valid-define-options: the identifiers of `<script setup>` inside one of the arguments that
// reference a variable `<script setup>` declares outside that argument (not an import; with
// `allow_const_literals`, not a `const` initialized with a literal), out of type annotations, in
// order. Each identifier is reported once per argument that contains it.
fn (mut c Checker) vx6_referencing_locally(root C.TSNode, t &estree.EsTree, s &VueScript, arguments []int, allow_const_literals bool) []int {
	mut out := []int{}
	if arguments.len == 0 {
		return out
	}
	tree := c.scope_tree(root)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .identifier || !s.in_script_setup(t, node) {
			continue
		}
		for argument in arguments {
			if !vx6_is_in_range(t, argument, node) {
				continue
			}
			v := c.unb_find_variable(root, t, node)
			if v < 0 {
				continue
			}
			ts := t.ts_node(node) or { continue }
			key := node_key(ts)
			variable := tree.variables[v]
			if variable.references.all(node_key(tree.references[it].identifier) != key) {
				continue
			}
			if variable.defs.len == 0 {
				continue
			}
			arg_start := t.nodes[argument].start
			arg_end := t.nodes[argument].end
			if variable.defs.any(it.kind == .import_binding
				|| !(s.setup_start <= treesitter.node_start(it.name)
					&& treesitter.node_end(it.name) <= s.setup_end)
				|| (arg_start <= treesitter.node_start(it.name)
					&& treesitter.node_end(it.name) <= arg_end)
				|| (allow_const_literals && c.vx6_is_const_literal(t, it))) {
				continue
			}
			if vx6_is_within_type_node(t, node) {
				continue
			}
			out << node
		}
	}
	return out
}

// vx6_is_const_literal: a definition `const x = <Literal>`.
fn (mut c Checker) vx6_is_const_literal(t &estree.EsTree, def ScopeDefinition) bool {
	if def.kind != .variable || def.parent_kind != 'const' {
		return false
	}
	init := def.init or { return false }
	es := c.es_index_of(t, unwrap_parens(init)) or { return false }
	return t.typ(es) == .literal
}

// vx6_v8_sort sorts the indexes 0..n the way V8's Array.prototype.sort (TimSort) orders an array
// of fewer than 64 elements with `cmp`: the run at the start (reversed when it descends), then a
// binary insertion of the others. A comparator that never answers 0 (`a > b ? 1 : -1`) puts equal
// elements in an order a stable sort would not, which the rules' reports depend on.
fn vx6_v8_sort(n int, cmp fn (int, int) int) []int {
	mut a := []int{len: n, init: index}
	if n < 2 {
		return a
	}
	mut run := 2
	descending := cmp(a[1], a[0]) < 0
	mut previous := a[1]
	for idx in 2 .. n {
		order := cmp(a[idx], previous)
		if (descending && order >= 0) || (!descending && order < 0) {
			break
		}
		previous = a[idx]
		run++
	}
	if descending {
		for i in 0 .. run / 2 {
			a[i], a[run - 1 - i] = a[run - 1 - i], a[i]
		}
	}
	for start in run .. n {
		pivot := a[start]
		mut left := 0
		mut right := start
		for left < right {
			mid := left + ((right - left) >> 1)
			if cmp(pivot, a[mid]) < 0 {
				right = mid
			} else {
				left = mid + 1
			}
		}
		for p := start; p > left; p-- {
			a[p] = a[p - 1]
		}
		a[left] = pivot
	}
	return a
}
