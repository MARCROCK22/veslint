module rules

import json2
import time

// Port of the `vue/no-potential-component-option-typo` rule of eslint-plugin-vue 10.12.1 (options
// `presets`, `custom` and `threshold`): a property of a Vue object whose name is not an option
// but is within `threshold` edits of some (lib/utils/vue-component-options.json), with a
// suggestion per option to rename it.

const vue_no_potential_component_option_typo_messages = {
	'potentialTypo': "'{{name}}' may be a typo, which is similar to option [{{option}}]."
}

// vue-component-options.json, by preset, in the file's order.
const vpcot_nuxt = ['asyncData', 'fetch', 'head', 'key', 'layout', 'loading', 'middleware',
	'scrollToTop', 'transition', 'validate', 'watchQuery']
const vpcot_vue_router = ['beforeRouteEnter', 'beforeRouteUpdate', 'beforeRouteLeave']
const vpcot_vue = ['data', 'props', 'propsData', 'computed', 'methods', 'watch', 'el', 'template',
	'render', 'renderError', 'staticRenderFns', 'beforeCreate', 'created', 'beforeDestroy', 'destroyed',
	'beforeMount', 'mounted', 'beforeUpdate', 'updated', 'activated', 'deactivated', 'errorCaptured',
	'serverPrefetch', 'directives', 'components', 'transitions', 'filters', 'provide', 'inject',
	'model', 'parent', 'mixins', 'name', 'extends', 'delimiters', 'comments', 'inheritAttrs', 'setup',
	'emits', 'beforeUnmount', 'unmounted', 'renderTracked', 'renderTriggered']

struct VpcotOptions {
	candidates []string
	threshold  f64
}

fn vue_no_potential_component_option_typo_options(options []json2.Any) !VpcotOptions {
	o := option_object(vue_no_potential_component_option_typo, options, ['presets', 'custom',
		'threshold'])!
	mut candidates := []string{}
	mut seen := map[string]bool{}
	for name in o.string_list('custom')! {
		if name !in seen {
			seen[name] = true
			candidates << name
		}
	}
	presets := if 'presets' in o.values { o.string_list('presets')! } else { ['vue'] }
	for preset in presets {
		lists := match preset {
			'all' { [vpcot_nuxt, vpcot_vue_router, vpcot_vue] }
			'vue' { [vpcot_vue] }
			'vue-router' { [vpcot_vue_router] }
			'nuxt' { [vpcot_nuxt] }
			else { [][]string{} }
		}
		for list in lists {
			for name in list {
				if name !in seen {
					seen[name] = true
					candidates << name
				}
			}
		}
	}
	mut threshold := 1.0
	if value := o.values['threshold'] {
		// `option.threshold || 1`: 0 is not a threshold.
		n := json_number(value)
		if n != 0 {
			threshold = n
		}
	}
	return VpcotOptions{
		candidates: candidates
		threshold:  threshold
	}
}

struct VpcotTypo {
	option   string
	distance int
	index    int
}

fn (mut c Checker) lint_vue_no_potential_component_option_typo(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_no_potential_component_option_typo_options(c.rule_options(vue_no_potential_component_option_typo))!
	mut findings := []Finding{}
	if o.candidates.len == 0 {
		return findings
	}
	s := c.vue_script(root, abs_path) or { return findings }
	t := c.es_tree(root, abs_path) or { return findings }
	for obj in s.objects_of(vue_all_object_types) {
		for p in t.list(obj, .properties) or { []int{} } {
			if t.typ(p) != .property {
				continue
			}
			name := vue_static_property_name(t, p) or { continue }
			key := t.node(p, .key) or { continue }
			stats.checked++
			if name in o.candidates {
				continue
			}
			mut typos := []VpcotTypo{}
			for option in o.candidates {
				distance := vx6_edit_distance(option, name)
				if f64(distance) <= o.threshold && distance > 0 {
					typos << VpcotTypo{
						option:   option
						distance: distance
						index:    typos.len
					}
				}
			}
			if typos.len == 0 {
				continue
			}
			typos.sort_with_compare(fn (a &VpcotTypo, b &VpcotTypo) int {
				// A stable sort, as JavaScript's.
				return if a.distance != b.distance {
					a.distance - b.distance
				} else {
					a.index - b.index
				}
			})
			mut suggestions := []Suggestion{}
			for typo in typos {
				suggestions << Suggestion{
					desc: "Replace property '${name}' to '${typo.option}'"
					fix:  fix_replace_range(t.nodes[key].start, t.nodes[key].end, typo.option)
				}
			}
			findings << Finding{
				stmt:        c.es_tree_position(t, key)
				message_id:  'potentialTypo'
				data:        {
					'name':   name
					'option': typos.map(it.option).join(',')
				}
				suggestions: suggestions
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
