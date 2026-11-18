module rules

import estree
import time

// Port of the `vue/prefer-define-options` rule of eslint-plugin-vue 10.12.1 (no options): in a
// file with `<script setup>`, an `export default`, with the fix that moves its declaration into
// a `defineOptions(…)` of `<script setup>` (none when the file calls defineOptions already).

const vue_prefer_define_options_messages = {
	'preferDefineOptions': 'Use `defineOptions` instead of default export.'
}

fn (mut c Checker) lint_vue_prefer_define_options(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	if !s.has_setup {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut export_default := -1
	for statement in t.list(t.root, .body) or { []int{} } {
		if t.typ(statement) == .export_default_declaration {
			export_default = statement
		}
	}
	stats.checked++
	if export_default < 0 {
		return findings
	}
	finding := c.vue_report(t.nodes[export_default].start, t.nodes[export_default].end,
		'preferDefineOptions', {})
	if c.vue_macros_named(t, 'defineOptions').len > 0 {
		findings << finding
	} else {
		findings << c.with_fixes(finding, c.vpdo_fix(t, s, export_default))!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vpdo_fix is the rule's buildFix: remove the declaration (the whole other <script> when it holds
// nothing else, and the white space before it on its line with the line break before it), and
// write `defineOptions(…)` after the last import of `<script setup>` or after its start tag.
fn (mut c Checker) vpdo_fix(t &estree.EsTree, s &VueScript, node int) []Fix {
	doc := c.vue.doc
	mut remove_start := t.nodes[node].start
	mut remove_end := t.nodes[node].end
	for child in doc.nodes[0].children {
		element := &doc.nodes[child]
		if element.typ != .v_element || element.name != 'script'
			|| c.vue_has_attribute(child, 'setup', none) {
			continue
		}
		if element.end_tag >= 0 {
			tokens := c.un_tokens(t)
			start_tag_end := doc.nodes[element.start_tag].end
			end_tag_start := doc.nodes[element.end_tag].start
			mut all_inside := true
			for token in tokens.all {
				if token.start >= start_tag_end && token.end <= end_tag_start
					&& !(remove_start <= token.start && token.end <= remove_end) {
					all_inside = false
					break
				}
			}
			if all_inside {
				remove_start = element.start
				remove_end = element.end
			}
		}
		break
	}
	line_start := vx6_line_start_index(c.src, remove_start)
	if js_trim(c.src[line_start..remove_start]) == '' {
		remove_start = if line_start == 0 { 0 } else { vx6_previous_line_end(c.src, line_start) }
	}
	imports := s.vx6_script_setup_imports(t)
	insert_at := if imports.len > 0 {
		t.nodes[imports.last()].end
	} else {
		doc.nodes[doc.nodes[s.setup_element].start_tag].end
	}
	declaration := t.node(node, .declaration) or { return [] }
	return [fix_remove_range(remove_start, remove_end),
		fix_insert_at(insert_at, '\ndefineOptions(${c.vx6_raw(t, declaration)})\n')]
}
