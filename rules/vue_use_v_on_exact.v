module rules

import time

// Port of the `vue/use-v-on-exact` rule of eslint-plugin-vue 10.12.1: among the `v-on` of a
// start tag for the same event (only `.native` ones on a custom component), when one has a system
// modifier (ctrl, shift, alt, meta), each one whose system modifiers are a part of another's (and
// not the same) without `.exact`, reported at its directive key.

const vuvoe_messages = {
	'considerExact': "Consider to use '.exact' modifier."
}

const vuvoe_system_modifiers = ['ctrl', 'shift', 'alt', 'meta']
const vuvoe_global_modifiers = ['stop', 'prevent', 'capture', 'self', 'once', 'passive', 'native']

struct VuvoeEvent {
	name        string
	key         int
	modifiers   []string
	has_handler bool
}

fn vuvoe_system_string(modifiers []string) string {
	mut out := modifiers.filter(it in vuvoe_system_modifiers)
	out.sort()
	return out.join(',')
}

fn vuvoe_key_string(modifiers []string) string {
	mut out := modifiers.filter(it !in vuvoe_global_modifiers && it !in vuvoe_system_modifiers)
	// localeCompare's order: only the equality of the two lists matters here.
	out.sort()
	return out.join(',')
}

fn vuvoe_global_only_keyboard_stop(e VuvoeEvent) bool {
	return e.name in ['keydown', 'keypress', 'keyup'] && 'stop' in e.modifiers && !e.has_handler
		&& e.modifiers.all(it in vuvoe_global_modifiers)
}

fn vuvoe_conflicted(base VuvoeEvent, e VuvoeEvent) bool {
	if e.key == base.key || 'exact' in e.modifiers
		|| ('exact' in base.modifiers && vuvoe_global_only_keyboard_stop(e)) {
		return false
	}
	e_keys := vuvoe_key_string(e.modifiers)
	base_keys := vuvoe_key_string(base.modifiers)
	if e_keys != '' && base_keys != '' && e_keys != base_keys {
		return false
	}
	e_system := vuvoe_system_string(e.modifiers)
	base_system := vuvoe_system_string(base.modifiers)
	return base.modifiers.len > 0 && base_system != e_system && base_system.contains(e_system)
}

fn (mut c Checker) lint_vue_use_v_on_exact(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_start_tag || node.attributes.len == 0 {
			continue
		}
		stats.checked++
		element := node.parent
		custom := c.vue_is_custom_component(element, false)
		mut events := []VuvoeEvent{}
		for a in node.attributes {
			if !c.vue_is_directive(a, 'on') {
				continue
			}
			attr := &c.vue.doc.nodes[a]
			key := &c.vue.doc.nodes[attr.key]
			modifiers := key.modifiers.map(c.vue.doc.nodes[it].name)
			if custom && 'native' !in modifiers {
				continue
			}
			events << VuvoeEvent{
				name:        if key.argument >= 0 { c.vue_vnode_text(key.argument) } else { '' }
				key:         attr.key
				modifiers:   modifiers
				has_handler: attr.value >= 0
			}
		}
		// groupEvents: the groups in the order their names first appear.
		mut event_names := []string{}
		for e in events {
			if e.name !in event_names {
				event_names << e.name
			}
		}
		for name in event_names {
			group := events.filter(it.name == name)
			if !group.any(it.modifiers.any(it in vuvoe_system_modifiers)) {
				continue
			}
			mut conflicted := []int{}
			for base in group {
				for k, e in group {
					if k !in conflicted && vuvoe_conflicted(base, e) {
						conflicted << k
					}
				}
			}
			for k in conflicted {
				findings << c.vue_report_vnode(group[k].key, 'considerExact', map[string]string{})
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
