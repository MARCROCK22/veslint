module rules

import time

// Port of the `vue/no-empty-component-block` rule of eslint-plugin-vue 10.12.1 (no options): a
// top-level `<template>`, `<script>` or `<style>` without content (or only white space) and
// without a non-empty `src`, with the fix that removes it.

const vue_no_empty_component_block_messages = {
	'unexpected': '`<{{ blockName }}>` is empty. Empty block is not allowed.'
}

fn (mut c Checker) lint_vue_no_empty_component_block(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	doc := c.vue.doc
	for block in doc.nodes[0].children {
		node := &doc.nodes[block]
		if node.typ != .v_element || node.name !in ['template', 'script', 'style']
			|| c.vue_has_attribute_src(block) {
			continue
		}
		stats.checked++
		children := node.children
		only_space := children.len == 1 && doc.nodes[children[0]].typ == .v_text
			&& js_trim(doc.nodes[children[0]].text) == ''
		if only_space || children.len == 0 {
			finding := c.vue_report_vnode(block, 'unexpected', {
				'blockName': node.name
			})
			findings << c.with_fixes(finding, [fix_remove_range(node.start, node.end)])!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_has_attribute_src is the rule's hasAttributeSrc: a plain `src` attribute with a non-empty
// value.
fn (c &Checker) vue_has_attribute_src(element int) bool {
	doc := c.vue.doc
	for a in c.vue_attributes(element) {
		attr := &doc.nodes[a]
		if !attr.directive && doc.nodes[attr.key].name == 'src' && attr.value >= 0
			&& doc.nodes[attr.value].text != '' {
			return true
		}
	}
	return false
}
