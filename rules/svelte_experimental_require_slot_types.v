module rules

// Port of the `svelte/experimental-require-slot-types` rule of eslint-plugin-svelte 3.24.1: a
// TypeScript component (outside runes mode) with a <slot> must declare the $$Slots interface or
// type, reported at line 1, column 1.

const serst_messages = {
	'missingSlotsInterface': 'The component must define the \$\$Slots interface.'
}

fn (mut c Checker) lint_svelte_experimental_require_slot_types(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	// conditions: Svelte 3/4, or Svelte 5 outside runes mode.
	if !c.is_svelte() || c.sv_runes() {
		return []
	}
	doc := c.svelte.doc
	mut is_ts := false
	mut has_slot := false
	for i in c.sv_snodes() {
		n := doc.nodes[i]
		if n.typ == .script_element {
			lang := (c.sv_lang_value(i) or { '' }).to_lower()
			is_ts = lang == 'ts' || lang == 'typescript'
		}
		if n.typ == .element && !n.name_ref.es && n.name_ref.idx >= 0
			&& doc.nodes[n.name_ref.idx].typ == .name && doc.nodes[n.name_ref.idx].name == 'slot' {
			has_slot = true
		}
	}
	if !is_ts || !has_slot || c.serst_declares_type('\$\$Slots') {
		return []
	}
	src := doc.src
	// The second character of the first line, for the order of the findings.
	start := if src.len > 0 && src[0] != `\n` && src[0] != `\r` { 1 } else { 0 }
	return [
		Finding{
			stmt:         c.position_range(start, start)
			message_id:   'missingSlotsInterface'
			fixed_line:   1
			fixed_column: 2
			no_end:       true
		},
	]
}

// serst_declares_type (also experimental-require-strict-events') tells whether an interface or a type alias of the document has that name.
fn (c &Checker) serst_declares_type(name string) bool {
	es := &c.svelte.doc.es
	for i, n in es.nodes {
		if n.typ in [.ts_interface_declaration, .ts_type_alias_declaration] {
			id := es.node(i, .id) or { continue }
			if (es.string_of(id, .name) or { '' }) == name {
				return true
			}
		}
	}
	return false
}
