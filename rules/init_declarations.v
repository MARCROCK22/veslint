module rules

import estree
import json2
import time

// Port of the `init-declarations` rule of typescript-eslint 8.72.2, which extends the rule of
// ESLint 10.15.0 with the same name (ported here too): in mode 'always' the wrapper also skips the
// declarations in a declared namespace, and reports an uninitialized declarator on its name only.
// The wrapper has no meta.defaultOptions, so the core rule reads the options as written: without
// options it has no mode and reports nothing.

const tsid_messages = {
	'initialized':    "Variable '{{idName}}' should be initialized on declaration."
	'notInitialized': "Variable '{{idName}}' should not be initialized on declaration."
}

struct TsidOptions {
	mode                 string // the wrapper's ('always' by default)
	core_mode            string // the core rule's: the first option as written, or ''
	ignore_for_loop_init bool
}

// tsid_options reads the merged options and, after them, the written ones (effective_options).
fn tsid_options(options []json2.Any) !TsidOptions {
	mode := if options.len > 0 && options[0] is string { options[0].str() } else { 'always' }
	if mode !in ['always', 'never'] {
		return error('the first option of `${init_declarations}` must be "always" or "never"')
	}
	mut core_mode := ''
	mut ignore := false
	if options.len > 1 && options[1] is []json2.Any {
		written := options[1].as_array()
		if written.len > 0 {
			core_mode = written[0].str()
		}
		if written.len > 1 {
			o := option_object(init_declarations, written[1..], ['ignoreForLoopInit'])!
			ignore = o.bool_value('ignoreForLoopInit')!
		}
	}
	return TsidOptions{
		mode:                 mode
		core_mode:            core_mode
		ignore_for_loop_init: ignore
	}
}

fn (mut c Checker) lint_init_declarations(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := tsid_options(c.rule_options(init_declarations))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut checked := 0
	// The core rule's flag: set when entering a declared TSModuleDeclaration, cleared when leaving
	// one.
	mut inside_declared_namespace := false
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if typ == .ts_module_declaration && (t.flag(node, .declare_) or { false }) {
			inside_declared_namespace = !step.leave
			continue
		}
		if !step.leave || typ != .variable_declaration {
			continue
		}
		checked++
		declare := t.flag(node, .declare_) or { false }
		if o.mode == 'always' && (declare || tsid_is_ancestor_namespace_declared(t, node)) {
			continue
		}
		// The core rule's VariableDeclaration:exit.
		if declare || inside_declared_namespace {
			continue
		}
		kind := t.string_of(node, .kind) or { '' }
		parent := t.nodes[node].parent
		is_ignored_for_loop := o.ignore_for_loop_init && parent >= 0 && tsid_is_for_loop(t, parent)
		for declaration in t.list(node, .declarations) or { []int{} } {
			id := t.node(declaration, .id) or { continue }
			initialized := tsid_is_initialized(t, declaration)
			mut message_id := ''
			if o.core_mode == 'always' && !initialized {
				message_id = 'initialized'
			} else if o.core_mode == 'never' && kind !in ['const', 'using', 'await using']
				&& initialized && !is_ignored_for_loop {
				message_id = 'notInitialized'
			}
			if t.typ(id) != .identifier || message_id == '' {
				continue
			}
			name := t.string_of(id, .name) or { '' }
			start := t.nodes[declaration].start
			// The wrapper reports a declarator without initializer on its name (as many UTF-16
			// units from its start), not on its type annotation.
			end := if t.node(declaration, .init) == none {
				tsid_advance_units(c.src, start, utf16_units(name).len)
			} else {
				t.nodes[declaration].end
			}
			findings << Finding{
				stmt:       c.position_range(start, end)
				message_id: message_id
				data:       {
					'idName': name
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

fn tsid_is_ancestor_namespace_declared(t &estree.EsTree, node int) bool {
	mut ancestor := t.nodes[node].parent
	for ancestor >= 0 {
		if t.typ(ancestor) == .ts_module_declaration && (t.flag(ancestor, .declare_) or { false }) {
			return true
		}
		ancestor = t.nodes[ancestor].parent
	}
	return false
}

fn tsid_is_for_loop(t &estree.EsTree, node int) bool {
	return t.typ(node) in [.for_in_statement, .for_of_statement, .for_statement]
}

// tsid_is_initialized ports isInitialized: a declarator of the head of a loop is initialized.
fn tsid_is_initialized(t &estree.EsTree, node int) bool {
	declaration := t.nodes[node].parent
	block := if declaration >= 0 { t.nodes[declaration].parent } else { -1 }
	if block >= 0 && tsid_is_for_loop(t, block) {
		if t.typ(block) == .for_statement {
			return (t.node(block, .init) or { -1 }) == declaration
		}
		return (t.node(block, .left) or { -1 }) == declaration
	}
	return t.node(node, .init) != none
}

// tsid_advance_units is the byte offset `units` UTF-16 units after `start`.
fn tsid_advance_units(src string, start int, units int) int {
	mut i := start
	mut count := 0
	for count < units && i < src.len {
		b := src[i]
		len := if b < 0x80 {
			1
		} else if b < 0xe0 {
			2
		} else if b < 0xf0 {
			3
		} else {
			4
		}
		count += if len == 4 { 2 } else { 1 }
		i += len
	}
	return if i > src.len { src.len } else { i }
}
