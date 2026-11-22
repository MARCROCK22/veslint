module rules

import time

// Port of the `vue/v-if-else-key` rule of eslint-plugin-vue 10.12.1: a custom component used more
// than once with v-if / v-else-if / v-else in the same scope (the elements between two custom
// components without a condition), whose element is in the conditional family of its parent and
// has no `key`: reported at its start tag, fixed by a `key="<kebab-name>-<n>"` after its name.

const vviek_messages = {
	'requireKey': "Conditionally rendered repeated component '{{componentName}}' expected to have a 'key' attribute."
}

struct VviekFamily {
mut:
	if_node   int
	else_ifs  []int
	else_node int = -1
}

struct VviekUsage {
mut:
	count int
	first int = -1
}

fn (c &Checker) vviek_has_condition(element int) bool {
	return c.vue_has_directive(element, 'if', none) || c.vue_has_directive(element, 'else-if', none)
		|| c.vue_has_directive(element, 'else', none)
}

fn (c &Checker) vviek_check(element int, name string, key string, families map[int]VviekFamily, mut findings []Finding) ! {
	node := &c.vue.doc.nodes[element]
	parent := node.parent
	if parent < 0 || c.vue.doc.nodes[parent].typ != .v_element {
		return
	}
	// hasConditionalRenderedSiblings
	mut has_siblings := false
	for s in c.vue.doc.nodes[parent].children {
		sn := &c.vue.doc.nodes[s]
		if s != element && sn.typ == .v_element && sn.raw_name == name && c.vviek_has_condition(s) {
			has_siblings = true
			break
		}
	}
	if !has_siblings {
		return
	}
	family := families[parent] or { return }
	if c.vue_has_attribute(element, 'key', none) || c.vue_has_directive(element, 'bind', 'key') {
		return
	}
	if family.if_node != element && family.else_node != element && element !in family.else_ifs {
		return
	}
	start_tag := &c.vue.doc.nodes[node.start_tag]
	at := start_tag.start + name.len + 1
	findings << c.with_fixes(c.vue_report_vnode(node.start_tag, 'requireKey', {
		'componentName': name
	}), [fix_insert_at(at, ' key="${key}"')])!
}

fn (mut c Checker) lint_vue_v_if_else_key(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	mut families := map[int]VviekFamily{}
	mut usage_stack := [map[string]VviekUsage{}]
	mut pushed := map[int]bool{}
	exempt := ['component', 'slot', 'template']
	for step in c.vue_template_steps() {
		if step.node.kind != .vnode {
			continue
		}
		i := step.node.v
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_element || node.raw_name in exempt {
			continue
		}
		custom := c.vue_is_custom_component(i, false)
		has_condition := c.vviek_has_condition(i)
		if step.leave {
			if custom && !has_condition {
				if usage_stack.len > 0 {
					usage_stack.pop()
				}
				continue
			}
			if !custom || i !in pushed {
				continue
			}
			if usage_stack.len > 0 {
				usage_stack.pop()
			}
			pushed.delete(i)
			continue
		}
		stats.checked++
		mut condition := c.vue_get_directive(i, 'if', none)
		if condition < 0 {
			condition = c.vue_get_directive(i, 'else-if', none)
		}
		if condition < 0 {
			condition = c.vue_get_directive(i, 'else', none)
		}
		if condition >= 0 && node.parent >= 0 && c.vue.doc.nodes[node.parent].typ == .v_element {
			kind := c.vue_directive_name(condition)
			if node.parent !in families {
				families[node.parent] = VviekFamily{
					if_node: i
				}
			}
			match kind {
				'if' {
					families[node.parent] = VviekFamily{
						if_node: i
					}
				}
				'else-if' {
					mut f := families[node.parent] or { VviekFamily{} }
					f.else_ifs << i
					families[node.parent] = f
				}
				'else' {
					mut f := families[node.parent] or { VviekFamily{} }
					f.else_node = i
					families[node.parent] = f
				}
				else {}
			}
		}
		if custom && !has_condition {
			usage_stack << map[string]VviekUsage{}
			continue
		}
		if !custom {
			continue
		}
		name := node.raw_name
		mut usage := if usage_stack.len > 0 {
			usage_stack[usage_stack.len - 1][name] or { VviekUsage{} }
		} else {
			VviekUsage{}
		}
		if has_condition {
			if usage.count == 0 {
				usage.first = i
			}
			if usage.count > 0 {
				c.vviek_check(i, name, '${vue_kebab_case(name)}-${usage.count + 1}', families, mut
					findings)!
				if usage.count == 1 {
					c.vviek_check(usage.first, name, '${vue_kebab_case(name)}-1', families, mut
						findings)!
				}
			}
			usage.count++
			if usage_stack.len > 0 {
				usage_stack[usage_stack.len - 1][name] = usage
			}
		}
		usage_stack << map[string]VviekUsage{}
		pushed[i] = true
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
