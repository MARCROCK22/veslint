module rules

import time

// Port of the `vue/static-class-names-order` rule of eslint-plugin-vue 10.12.1: a static `class`
// attribute whose class names are not in the order of String.prototype.localeCompare, fixed by
// sorting them, joined with the first run of white space of the value.

const vscno_messages = {
	'shouldBeOrdered': 'Classes should be ordered alphabetically.'
}

// vscno_split_keeping_spaces is `text.split(/(\s+)/)`: the pieces and, between them, the runs of
// white space.
fn vscno_split_keeping_spaces(text string) []string {
	mut out := []string{}
	mut piece := []rune{}
	mut in_space := false
	for r in text.runes() {
		space := is_js_space(r)
		if space != in_space {
			out << piece.string()
			piece = []rune{}
			in_space = space
		}
		piece << r
	}
	out << piece.string()
	if in_space {
		// A trailing run is followed by an empty piece.
		out << ''
	}
	return out
}

// vscno_sorted is Array.prototype.sort with localeCompare: a stable insertion sort.
fn vscno_sorted(names []string) []string {
	mut out := names.clone()
	for i in 1 .. out.len {
		item := out[i]
		mut j := i - 1
		for j >= 0 && js_locale_compare(out[j], item) > 0 {
			out[j + 1] = out[j]
			j--
		}
		out[j + 1] = item
	}
	return out
}

fn (mut c Checker) lint_vue_static_class_names_order(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_attribute || node.directive || c.vue.doc.nodes[node.key].name != 'class'
			|| node.value < 0 {
			continue
		}
		stats.checked++
		class_list := c.vue.doc.nodes[node.value].text
		pieces := vscno_split_keeping_spaces(class_list)
		divider := if pieces.len > 1 { pieces[1] } else { '' }
		class_names := pieces.filter(js_trim(it) != '')
		sorted := vscno_sorted(class_names).join(divider)
		if class_list == sorted {
			continue
		}
		value := &c.vue.doc.nodes[node.value]
		findings << c.with_fixes(c.vue_report_vnode(i, 'shouldBeOrdered', {}), [
			fix_replace_range(value.start, value.end, '"${sorted}"'),
		])!
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
