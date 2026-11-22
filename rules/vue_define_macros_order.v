module rules

import estree
import json2
import time

// Port of the `vue/define-macros-order` rule of eslint-plugin-vue 10.12.1 (options `order`, by
// default ["defineProps", "defineEmits"], and `defineExposeLast`): the statements of the
// compiler macros (and of other calls the order names) of `<script setup>` must come first, in
// that order, with the fix that moves them; with `defineExposeLast`, defineExpose must be the last
// statement, with a suggestion that moves it there.

const vue_define_macros_order_messages = {
	'macrosNotAtTop':         '{{macro}} should be placed at the top of `<script setup>` (after any potential import statements or type definitions).'
	'macrosUnordered':        '{{macro}} should be above {{before}}.'
	'defineExposeNotTheLast': '`defineExpose` should be the last statement in `<script setup>`.'
	'putExposeAtTheLast':     'Put `defineExpose` as the last statement in `<script setup>`.'
}

const vdmo_known_macros = ['defineEmits', 'defineProps', 'defineOptions', 'defineSlots', 'defineModel',
	'defineExpose']

struct VdmoOptions {
	order       []string
	expose_last bool
}

fn vue_define_macros_order_options(options []json2.Any) !VdmoOptions {
	o := option_object(vue_define_macros_order, options, ['order', 'defineExposeLast'])!
	order := if 'order' in o.values {
		o.string_list('order')!
	} else {
		['defineProps', 'defineEmits']
	}
	expose_last := o.bool_value('defineExposeLast')!
	if expose_last && 'defineExpose' in order {
		return error("`defineExpose` macro can't be in the `order` array if `defineExposeLast` is true.")
	}
	return VdmoOptions{
		order:       if order.len > 0 { order } else { ['defineProps', 'defineEmits'] }
		expose_last: expose_last
	}
}

// vdmo_statement is getDefineMacrosStatement: the statement of the program the node is in.
fn vdmo_statement(t &estree.EsTree, node int) int {
	mut n := node
	for n >= 0 {
		parent := t.nodes[n].parent
		if parent >= 0 && t.typ(parent) == .program {
			return n
		}
		n = parent
	}
	return -1
}

struct VdmoMacro {
	name string
	node int
}

fn (mut c Checker) lint_vue_define_macros_order(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	o := vue_define_macros_order_options(c.rule_options(vue_define_macros_order))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	body := t.list(t.root, .body) or { []int{} }
	mut macros := map[string][]int{}
	mut expose_node := -1
	// The macros on their exit, the other calls of the order on their enter: in the order of
	// the program, a call ends after the calls it contains start.
	mut events := []VdmoMacro{}
	for m in c.vue_macros(t) {
		events << VdmoMacro{m.name, m.call}
	}
	for statement in body {
		if !s.in_script_setup(t, statement) {
			continue
		}
		mut call := -1
		if t.typ(statement) == .expression_statement {
			call = t.node(statement, .expression) or { -1 }
		}
		if call >= 0 && t.typ(call) == .call_expression {
			c.vdmo_custom(t, call, o, mut events)
		}
		if t.typ(statement) == .variable_declaration {
			for declarator in t.list(statement, .declarations) or { []int{} } {
				init := t.node(declarator, .init) or { continue }
				if t.typ(init) == .call_expression {
					c.vdmo_custom(t, init, o, mut events)
				}
			}
		}
	}
	events.sort_with_compare(fn [t] (a &VdmoMacro, b &VdmoMacro) int {
		// A macro is known on its exit, another call on its enter.
		ka := if a.name in vdmo_known_macros { t.nodes[a.node].end } else { t.nodes[a.node].start }
		kb := if b.name in vdmo_known_macros { t.nodes[b.node].end } else { t.nodes[b.node].start }
		return ka - kb
	})
	for e in events {
		statement := vdmo_statement(t, e.node)
		if e.name == 'defineModel' {
			macros['defineModel'] << statement
		} else if e.name == 'defineExpose' {
			expose_node = statement
		} else {
			macros[e.name] = [statement]
		}
	}
	stats.checked++
	mut first_index := -1
	for i, item in body {
		if s.in_script_setup(t, item) && !vdmo_is_skipped(t, item) {
			first_index = i
			break
		}
	}
	mut ordered := []VdmoMacro{}
	for name in o.order {
		for node in macros[name] or { []int{} } {
			if node >= 0 {
				ordered << VdmoMacro{name, node}
			}
		}
	}
	tokens := c.un_tokens(t)
	if o.expose_last && body.len > 0 && expose_node >= 0 && body.last() != expose_node {
		mut suggestions := []Suggestion{}
		if fixes := c.vdmo_move_to_last(t, tokens, expose_node, body.last()) {
			ok, suggestion := c.suggestion('putExposeAtTheLast', {}, fixes)!
			if ok {
				suggestions << suggestion
			}
		}
		findings << Finding{
			stmt:        c.es_tree_position(t, expose_node)
			message_id:  'defineExposeNotTheLast'
			suggestions: suggestions
		}
	}
	for index, should in ordered {
		target_index := first_index + index
		if target_index < 0 || target_index >= body.len {
			break
		}
		target := body[target_index]
		if should.node == target {
			continue
		}
		mut move_nodes := ordered[index..].map(it.node)
		target_in := move_nodes.index(target)
		if target_in >= 0 {
			move_nodes = move_nodes[..target_in].clone()
		}
		mut before_macro := ''
		for name in o.order {
			if target in (macros[name] or { []int{} }) {
				before_macro = name
				break
			}
		}
		mut data := {
			'macro': should.name
		}
		if before_macro != '' {
			data['before'] = before_macro
		}
		mut fixes := []Fix{}
		for node in move_nodes {
			fixes << c.vdmo_move_before(t, tokens, node, target) or { []Fix{} }
		}
		findings << c.with_fixes(Finding{
			stmt:       c.es_tree_position(t, move_nodes[0])
			message_id: if before_macro != '' { 'macrosUnordered' } else { 'macrosNotAtTop' }
			data:       data
		}, fixes)!
		break
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vdmo_custom records a call of the order that is not a macro of Vue.
fn (c &Checker) vdmo_custom(t &estree.EsTree, call int, o &VdmoOptions, mut events []VdmoMacro) {
	name := vue_callee_name(t, call)
	if name != '' && name in o.order && name !in vdmo_known_macros {
		events << VdmoMacro{name, call}
	}
}

// vdmo_is_skipped: a statement getTargetStatementPosition skips (imports, types, `declare`,
// 'use strict'…).
fn vdmo_is_skipped(t &estree.EsTree, node int) bool {
	if t.typ(node) in [.import_declaration, .ts_enum_declaration, .ts_module_declaration,
		.ts_interface_declaration, .ts_type_alias_declaration, .debugger_statement, .empty_statement,
		.export_named_declaration] {
		return true
	}
	if t.flag(node, .declare_) or { false } {
		return true
	}
	if t.typ(node) == .expression_statement {
		expression := t.node(node, .expression) or { return false }
		if t.typ(expression) == .literal {
			value := t.get(expression, .value)
			return value is string && value == 'use strict'
		}
	}
	return false
}

// vdmo_line_start_index is getLineStartIndex: the end of `prev` when `token` starts on the line
// it ends on, else the start of the line of `token`.
fn (c &Checker) vdmo_line_start_index(t &estree.EsTree, token_start int, prev_end int) int {
	token_line, _ := t.line_column(token_start)
	prev_line, _ := t.line_column(prev_end)
	if token_line == prev_line {
		return prev_end
	}
	return vx6_line_start_index(c.src, token_start)
}

// vdmo_cut is the range moveNodeBefore and moveNodeToLast remove, and the token before the node.
fn (c &Checker) vdmo_cut(t &estree.EsTree, tokens &SourceTokens, node int) ?(int, int, SourceToken, SourceToken) {
	before := tokens.before(t.nodes[node].start, false)?
	node_comment := tokens.after(before.end, true)?
	next := tokens.after(t.nodes[node].end, true)?
	cut_start := c.vdmo_line_start_index(t, node_comment.start, before.end)
	cut_end := c.vdmo_line_start_index(t, next.start, t.nodes[node].end)
	return cut_start, cut_end, before, node_comment
}

fn (c &Checker) vdmo_move_before(t &estree.EsTree, tokens &SourceTokens, node int, target int) ?[]Fix {
	cut_start, cut_end, _, node_comment := c.vdmo_cut(t, tokens, node)?
	before_target := tokens.before(t.nodes[target].start, false)?
	target_comment := tokens.after(before_target.end, true)?
	text_node := c.src[node_comment.start..t.nodes[node].end]
	after_target := tokens.after(t.nodes[target].end, true)?
	after_text := c.src[t.nodes[target].end..after_target.start]
	invalid := !text_node.ends_with(';') && !after_text.contains('\n')
	insert := text_node + after_text + if invalid { ';' } else { '' }
	return [fix_insert_at(target_comment.start, insert), fix_remove_range(cut_start, cut_end)]
}

fn (c &Checker) vdmo_move_to_last(t &estree.EsTree, tokens &SourceTokens, node int, target int) ?[]Fix {
	cut_start, cut_end, before, _ := c.vdmo_cut(t, tokens, node)?
	text_node := c.src[before.end..t.nodes[node].end]
	return [fix_insert_at(t.nodes[target].end, text_node), fix_remove_range(cut_start, cut_end)]
}
