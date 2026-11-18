module rules

// Port of the `svelte/no-dupe-else-if-blocks` rule of eslint-plugin-svelte 3.24.1 (ESLint's
// no-dupe-else-if for `{#if}` / `{:else if}` chains): a condition that a previous condition of the
// chain covers (the same tokens, `||` and `&&` operands in any order) is reported.

const sndeib_messages = {
	'unexpected': 'This branch can never execute. Its condition is a duplicate or covered by previous conditions in the `{#if}` / `{:else if}` chain.'
}

// SndeibAnd is AndOperands: an operand of `||` split by `&&`.
struct SndeibAnd {
	node     int
	operands []int
}

// SndeibOr is OrOperands: a condition split by `||`, each split by `&&`.
struct SndeibOr {
	node int
mut:
	operands []SndeibAnd
}

// sndeib_split is splitByLogicalOperator.
fn (c &Checker) sndeib_split(operator string, node int) []int {
	es := &c.svelte.doc.es
	if es.nodes[node].typ == .logical_expression && (es.string_of(node, .operator) or { '' }) == operator {
		mut out := c.sndeib_split(operator, es.node(node, .left) or { return [node] })
		out << c.sndeib_split(operator, es.node(node, .right) or { return [node] })
		return out
	}
	return [node]
}

fn (c &Checker) sndeib_or_operands(node int) SndeibOr {
	return SndeibOr{
		node:     node
		operands: c.sndeib_split('||', node).map(SndeibAnd{
			node:     it
			operands: c.sndeib_split('&&', it)
		})
	}
}

// sndeib_equal is the rule's equal().
fn (c &Checker) sndeib_equal(a int, b int) bool {
	es := &c.svelte.doc.es
	if c.svelte.doc.es_type_name(a) != c.svelte.doc.es_type_name(b) {
		return false
	}
	if es.nodes[a].typ == .logical_expression {
		op := es.string_of(a, .operator) or { '' }
		if (op == '||' || op == '&&') && op == (es.string_of(b, .operator) or { '' }) {
			al := es.node(a, .left) or { -1 }
			ar := es.node(a, .right) or { -1 }
			bl := es.node(b, .left) or { -1 }
			br := es.node(b, .right) or { -1 }
			return (c.sndeib_equal(al, bl) && c.sndeib_equal(ar, br))
				|| (c.sndeib_equal(al, br) && c.sndeib_equal(ar, bl))
		}
	}
	return c.sv_equal_tokens(es.nodes[a].start, es.nodes[a].end, es.nodes[b].start, es.nodes[b].end)
}

fn (c &Checker) sndeib_is_subset(a SndeibAnd, b SndeibAnd) bool {
	return a.operands.all(fn [c, b] (x int) bool {
		return b.operands.any(c.sndeib_equal(x, it))
	})
}

fn (mut c Checker) lint_svelte_no_dupe_else_if_blocks(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.if_block) {
		test := doc.nodes[i].expression
		if test.idx < 0 || !test.es {
			continue
		}
		mut conditions := []int{}
		if doc.es.nodes[test.idx].typ == .logical_expression
			&& (doc.es.string_of(test.idx, .operator) or { '' }) == '&&' {
			conditions << c.sndeib_split('&&', test.idx)
		}
		conditions << test.idx
		mut list := conditions.map(c.sndeib_or_operands(it))
		// iterateIfElseIf: up the chain of `{:else if}` blocks.
		mut target := i
		chain: for {
			parent := doc.nodes[target].parent
			if parent < 0 || doc.nodes[parent].typ != .else_block
				|| target !in doc.nodes[parent].children {
				break
			}
			block := doc.nodes[parent].parent
			if block < 0 || doc.nodes[block].typ != .if_block {
				break
			}
			target = block
			expression := doc.nodes[block].expression
			if expression.idx < 0 || !expression.es {
				continue
			}
			current := c.sndeib_or_operands(expression.idx)
			for k in 0 .. list.len {
				list[k].operands = list[k].operands.filter(fn [c, current] (or_operand SndeibAnd) bool {
					return !current.operands.any(c.sndeib_is_subset(it, or_operand))
				})
				if list[k].operands.len == 0 {
					findings << c.sv_report_es(list[k].node, 'unexpected', {})
					break chain
				}
			}
		}
	}
	return findings
}
