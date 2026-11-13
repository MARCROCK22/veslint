module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-lone-blocks` rule of ESLint 10.6.0 (it has no options).

const nlb_messages = {
	'redundantBlock':       'Block is redundant.'
	'redundantNestedBlock': 'Nested block is redundant.'
}

// NlbKind is what a tree-sitter `statement_block` is in ESTree.
enum NlbKind {
	block        // BlockStatement
	static_block // StaticBlock
	other        // the body of a namespace or `declare global`
}

fn nlb_kind(n C.TSNode) NlbKind {
	parent := node_parent(n) or { return .block }
	return match node_kind(parent) {
		'class_static_block' { .static_block }
		'internal_module', 'module', 'ambient_declaration' { .other }
		else { .block }
	}
}

struct NlbState {
	es6 bool
mut:
	lone     []u64 // the stack of lone blocks
	findings []Finding
}

fn (mut c Checker) lint_no_lone_blocks(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut st := NlbState{
		es6: c.ecma_version >= 2015
	}
	c.nlb_visit(root, root, mut st, mut stats)
	stats.eval_ms += ms(sw.elapsed())
	return st.findings
}

// nlb_statements are the statements of a block, program or switch case.
fn nlb_statements(n C.TSNode) []C.TSNode {
	mut out := []C.TSNode{}
	value := node_field(n, 'value')
	for child in named_children(n) {
		if node_kind(child) == 'comment' {
			continue
		}
		if v := value {
			if node_key(v) == node_key(child) {
				continue
			}
		}
		out << child
	}
	return out
}

// nlb_is_lone_block ports isLoneBlock.
fn nlb_is_lone_block(node C.TSNode) bool {
	parent := node_parent(node) or { return false }
	match node_kind(parent) {
		'program' {
			return true
		}
		'statement_block' {
			return nlb_kind(parent) != .other
		}
		'switch_case', 'switch_default' {
			consequent := nlb_statements(parent)
			return !(consequent.len == 1 && node_key(consequent[0]) == node_key(node))
		}
		else {
			return false
		}
	}
}

fn (c &Checker) nlb_report(node C.TSNode, mut st NlbState) {
	parent := node_parent(node) or { return }
	nested := node_kind(parent) == 'statement_block' && nlb_kind(parent) != .other
	st.findings << Finding{
		stmt:       position_of(node)
		message_id: if nested { 'redundantNestedBlock' } else { 'redundantBlock' }
	}
}

// nlb_mark ports markLoneBlock: a block-level binding whose parent is the innermost lone block
// makes it necessary.
fn nlb_mark(node C.TSNode, mut st NlbState) {
	if st.lone.len == 0 {
		return
	}
	parent := node_parent(node) or { return }
	if node_kind(parent) == 'statement_block' && st.lone.last() == node_key(parent) {
		st.lone.pop()
	}
}

fn (mut c Checker) nlb_visit(root C.TSNode, n C.TSNode, mut st NlbState, mut stats Stats) {
	kind := node_kind(n)
	is_block := kind == 'statement_block' && nlb_kind(n) == .block
	if is_block {
		stats.checked++
		if nlb_is_lone_block(n) {
			if st.es6 {
				st.lone << node_key(n)
			} else {
				c.nlb_report(n, mut st)
			}
		}
	}
	if st.es6 {
		match kind {
			'lexical_declaration' {
				nlb_mark(n, mut st)
			}
			'function_declaration', 'generator_function_declaration' {
				tree := c.scope_tree(root)
				if tree.is_strict(tree.get_scope(n)) {
					nlb_mark(n, mut st)
				}
			}
			'class_declaration', 'abstract_class_declaration' {
				nlb_mark(n, mut st)
			}
			else {}
		}
	}
	for child in named_children(n) {
		c.nlb_visit(root, child, mut st, mut stats)
	}
	if is_block && st.es6 {
		parent := node_parent(n) or { return }
		if st.lone.len > 0 && st.lone.last() == node_key(n) {
			st.lone.pop()
			c.nlb_report(n, mut st)
		} else if node_kind(parent) == 'statement_block' && nlb_kind(parent) != .other
			&& nlb_statements(parent).len == 1 {
			c.nlb_report(n, mut st)
		}
	}
}
