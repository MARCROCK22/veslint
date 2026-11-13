module rules

import json2
import time
import treesitter { named_children, node_kind, node_start }

// Port of the `grouped-accessor-pairs` rule of ESLint 10.6.0, with its options.

const gap_messages = {
	'notGrouped':   'Accessor pair {{ formerName }} and {{ latterName }} should be grouped.'
	'invalidOrder': 'Expected {{ latterName }} to be before {{ formerName }}.'
}

struct GapOptions {
	order                string
	enforce_for_ts_types bool
}

// gap_options reads the order and enforceForTSTypes.
fn gap_options(options []json2.Any) !GapOptions {
	order := if options.len > 0 { options[0] } else { json2.Any('anyOrder') }
	if order !is string || order.str() !in ['anyOrder', 'getBeforeSet', 'setBeforeGet'] {
		return error('the first option of `${grouped_accessor_pairs}` must be "anyOrder", "getBeforeSet" or "setBeforeGet"')
	}
	o := option_object(grouped_accessor_pairs, if options.len > 1 {
		options[1..]
	} else {
		[]json2.Any{}
	},
		['enforceForTSTypes'])!
	return GapOptions{
		order:                order.str()
		enforce_for_ts_types: o.bool_value('enforceForTSTypes')!
	}
}

// GapAccessor is a key with its getters and setters (indexes in the list).
struct GapAccessor {
	named  bool
	name   string
	tokens []string
mut:
	getters []int
	setters []int
}

fn (mut c Checker) lint_grouped_accessor_pairs(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := gap_options(c.rule_options(grouped_accessor_pairs))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['object', 'class_body', 'object_type', 'interface_body'], []) {
		stats.checked++
		members := named_children(node).filter(node_kind(it) !in ['comment', 'decorator'])
		match node_kind(node) {
			'object' {
				c.gap_check(o, members, members.map(node_kind(it) in ['pair', 'method_definition',
					'shorthand_property_identifier']), mut findings)
			}
			'class_body' {
				methods := members.map(node_kind(it) in ['method_definition', 'method_signature'])
				c.gap_check(o, members, []bool{len: members.len, init: methods[index]
					&& !es_is_static_member(members[index])}, mut findings)
				c.gap_check(o, members, []bool{len: members.len, init: methods[index]
					&& es_is_static_member(members[index])}, mut findings)
			}
			else {
				if o.enforce_for_ts_types {
					c.gap_check(o, members, members.map(node_kind(it) == 'method_signature'), mut
						findings)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// gap_check ports checkList: the getter and the setter of each key are next to each other, in the
// order of the option.
fn (mut c Checker) gap_check(o GapOptions, members []C.TSNode, checked []bool, mut findings []Finding) {
	mut accessors := []GapAccessor{}
	for i, member in members {
		if !checked[i] {
			continue
		}
		kind := es_accessor_kind(member)
		if kind !in ['get', 'set'] {
			continue
		}
		static_name := c.es_static_key_name(member)
		named := static_name != none
		name := static_name or { '' }
		mut tokens := []string{}
		if !named {
			key, _ := es_property_key(member) or { continue }
			for token in c.source_tokens(key).inside(node_start(key), c.es_end(key), false) {
				tokens << '${int(token.kind)}:${c.src[token.start..token.end]}'
			}
		}
		mut found := false
		for mut accessor in accessors {
			same := if accessor.named && named {
				accessor.name == name
			} else if !accessor.named && !named {
				accessor.tokens == tokens
			} else {
				false
			}
			if same {
				if kind == 'get' {
					accessor.getters << i
				} else {
					accessor.setters << i
				}
				found = true
				break
			}
		}
		if !found {
			accessors << GapAccessor{
				named:   named
				name:    name
				tokens:  tokens
				getters: if kind == 'get' { [i] } else { []int{} }
				setters: if kind == 'set' { [i] } else { []int{} }
			}
		}
	}
	for accessor in accessors {
		if accessor.getters.len != 1 || accessor.setters.len != 1 {
			continue
		}
		getter := accessor.getters[0]
		setter := accessor.setters[0]
		former := members[if getter < setter { getter } else { setter }]
		latter := members[if getter < setter { setter } else { getter }]
		distance := if getter > setter { getter - setter } else { setter - getter }
		mut message_id := ''
		if distance > 1 {
			message_id = 'notGrouped'
		} else if (o.order == 'getBeforeSet' && getter > setter)
			|| (o.order == 'setBeforeGet' && getter < setter) {
			message_id = 'invalidOrder'
		}
		if message_id != '' {
			findings << Finding{
				stmt:       c.es_function_head(latter)
				message_id: message_id
				data:       {
					'formerName': c.gap_name(former)
					'latterName': c.gap_name(latter)
				}
			}
		}
	}
}

// gap_name ports getFunctionNameWithKind for an accessor: `static`, `private`, getter or setter,
// and its name.
fn (c &Checker) gap_name(member C.TSNode) string {
	mut tokens := []string{}
	in_class := node_kind(member) in ['method_definition', 'method_signature']
		&& node_kind(cti_estree_parent(member) or { member }) == 'class_body'
	key, computed := es_property_key(member) or { return '' }
	private := !computed && node_kind(key) == 'private_property_identifier'
	if in_class {
		if es_is_static_member(member) {
			tokens << 'static'
		}
		if private {
			tokens << 'private'
		}
	}
	tokens << if es_accessor_kind(member) == 'get' { 'getter' } else { 'setter' }
	if node_kind(member) == 'method_signature' && !in_class {
		tokens << "'${c.es_static_key_name(member) or { 'null' }}'"
	} else if private {
		tokens << c.text(key)
	} else if name := c.es_static_key_name(member) {
		tokens << "'${name}'"
	}
	return tokens.join(' ')
}
