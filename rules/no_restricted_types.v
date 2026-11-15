module rules

import estree
import json2
import time

// Port of the `@typescript-eslint/no-restricted-types` rule of typescript-eslint 8.72.2, with its
// option `types` (messages, `fixWith` fixes and `suggest` suggestions).

const nrty_messages = {
	'bannedTypeMessage':     "Don't use `{{name}}` as a type.{{customMessage}}"
	'bannedTypeReplacement': 'Replace `{{name}}` with `{{replacement}}`.'
}

// nrty_type_keywords are TYPE_KEYWORDS.
const nrty_type_keywords = {
	'bigint':    estree.NodeType.ts_big_int_keyword
	'boolean':   estree.NodeType.ts_boolean_keyword
	'never':     estree.NodeType.ts_never_keyword
	'null':      estree.NodeType.ts_null_keyword
	'number':    estree.NodeType.ts_number_keyword
	'object':    estree.NodeType.ts_object_keyword
	'string':    estree.NodeType.ts_string_keyword
	'symbol':    estree.NodeType.ts_symbol_keyword
	'undefined': estree.NodeType.ts_undefined_keyword
	'unknown':   estree.NodeType.ts_unknown_keyword
	'void':      estree.NodeType.ts_void_keyword
}

// NrtyBan is the configuration of a banned type.
struct NrtyBan {
	custom_message string
	fix_with       string
	suggest        []string
	has_suggest    bool
}

// nrty_remove_spaces ports removeSpaces: without the characters of /\s/.
fn nrty_remove_spaces(s string) string {
	return s.runes().filter(!(is_js_space(it) || it in [rune(0x2028), rune(0x2029)])).string()
}

fn nrty_options(options []json2.Any) !map[string]NrtyBan {
	o := option_object(no_restricted_types, options, ['types'])!
	mut out := map[string]NrtyBan{}
	raw := o.values['types'] or { return out }
	if raw !is map[string]json2.Any {
		return error('option `types` of `${no_restricted_types}` must be an object')
	}
	for key, value in raw.as_map() {
		mut ban := NrtyBan{}
		match value {
			bool {
				if !value {
					return error('`types.${key}` of `${no_restricted_types}` must be true, a text or an object')
				}
			}
			string {
				ban = NrtyBan{
					custom_message: if value == '' { '' } else { ' ${value}' }
				}
			}
			map[string]json2.Any {
				mut message := ''
				mut fix_with := ''
				mut suggest := []string{}
				mut has_suggest := false
				for k, v in value {
					match k {
						'message', 'fixWith' {
							if v !is string {
								return error('`types.${key}.${k}` of `${no_restricted_types}` must be a text')
							}
							if k == 'message' {
								message = v as string
							} else {
								fix_with = v as string
							}
						}
						'suggest' {
							if v !is []json2.Any {
								return error('`types.${key}.suggest` of `${no_restricted_types}` must be a list of texts')
							}
							has_suggest = true
							for item in v.as_array() {
								if item !is string {
									return error('`types.${key}.suggest` of `${no_restricted_types}` must be a list of texts')
								}
								suggest << item as string
							}
						}
						else {
							return error('`types.${key}` of `${no_restricted_types}` has no `${k}`')
						}
					}
				}
				ban = NrtyBan{
					custom_message: if message == '' { '' } else { ' ${message}' }
					fix_with:       fix_with
					suggest:        suggest
					has_suggest:    has_suggest
				}
			}
			else {
				return error('`types.${key}` of `${no_restricted_types}` must be true, a text or an object')
			}
		}
		out[nrty_remove_spaces(key)] = ban
	}
	return out
}

fn (mut c Checker) lint_no_restricted_types(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	banned := nrty_options(c.rule_options(no_restricted_types))!
	mut findings := []Finding{}
	if banned.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	mut keywords := map[int]string{}
	for keyword, typ in nrty_type_keywords {
		if keyword in banned {
			keywords[int(typ)] = keyword
		}
	}
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		typ := t.typ(node)
		if keyword := keywords[int(typ)] {
			stats.checked++
			c.nrty_check(t, banned, node, keyword, mut findings)
			continue
		}
		match typ {
			.ts_class_implements, .ts_interface_heritage {
				stats.checked++
				c.nrty_check(t, banned, t.node(node, .expression) or { continue }, '', mut
					findings)
				if t.node(node, .type_arguments) != none {
					c.nrty_check(t, banned, node, '', mut findings)
				}
			}
			.ts_tuple_type {
				stats.checked++
				if (t.list(node, .element_types) or { []int{} }).len == 0 {
					c.nrty_check(t, banned, node, '', mut findings)
				}
			}
			.ts_type_literal {
				stats.checked++
				if (t.list(node, .members) or { []int{} }).len == 0 {
					c.nrty_check(t, banned, node, '', mut findings)
				}
			}
			.ts_type_reference {
				stats.checked++
				c.nrty_check(t, banned, t.node(node, .type_name) or { continue }, '', mut
					findings)
				if t.node(node, .type_arguments) != none {
					c.nrty_check(t, banned, node, '', mut findings)
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nrty_check ports checkBannedTypes (`name` '' for stringifyNode of the node).
fn (mut c Checker) nrty_check(t &estree.EsTree, banned map[string]NrtyBan, node int, keyword string, mut findings []Finding) {
	name := if keyword != '' {
		keyword
	} else {
		nrty_remove_spaces(c.src[t.nodes[node].start..t.nodes[node].end])
	}
	ban := banned[name] or { return }
	start := t.nodes[node].start
	end := t.nodes[node].end
	findings << Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  'bannedTypeMessage'
		data:        {
			'name':          name
			'customMessage': ban.custom_message
		}
		has_fix:     ban.fix_with != ''
		fix:         if ban.fix_with != '' {
			fix_replace_range(start, end, ban.fix_with)
		} else {
			Fix{}
		}
		suggestions: ban.suggest.map(Suggestion{
			message_id: 'bannedTypeReplacement'
			data:       {
				'name':        name
				'replacement': it
			}
			fix:        fix_replace_range(start, end, it)
		})
	}
}
