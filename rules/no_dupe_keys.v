module rules

import time
import treesitter { named_children, node_kind, position_of }

// Port of the `no-dupe-keys` rule of ESLint 10.6.0 (it has no options).

const ndk_messages = {
	'unexpected': "Duplicate key '{{name}}'."
}

struct NdkEntry {
mut:
	get bool
	set bool
}

fn (mut c Checker) lint_no_dupe_keys(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for object in c.nodes_of_kinds(root, ['object'], []) {
		stats.checked++
		mut entries := map[string]NdkEntry{}
		for property in named_children(object) {
			kind_of := node_kind(property)
			if kind_of !in ['pair', 'method_definition', 'shorthand_property_identifier'] {
				continue
			}
			name := c.es_static_key_name(property) or { continue }
			kind := es_accessor_kind(property)
			key, computed := es_property_key(property) or { continue }
			// `__proto__: x` sets the prototype; it is not a property.
			if name == '__proto__' && kind_of == 'pair' && !computed {
				continue
			}
			mut entry := entries[name] or { NdkEntry{} }
			if (kind in ['init', 'get'] && entry.get) || (kind in ['init', 'set'] && entry.set) {
				findings << Finding{
					stmt:       position_of(key)
					message_id: 'unexpected'
					data:       {
						'name': name
					}
				}
			}
			if kind in ['init', 'get'] {
				entry.get = true
			}
			if kind in ['init', 'set'] {
				entry.set = true
			}
			entries[name] = entry
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
