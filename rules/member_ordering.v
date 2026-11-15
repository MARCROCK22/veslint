module rules

import estree
import json2
import jsregexp
import time

// Port of the `@typescript-eslint/member-ordering` rule of typescript-eslint 8.72.2, with all its
// options. Its natural orders compare names with natural-compare 1.4.0 (mord_natural_compare),
// its alphabetical orders with JavaScript's `<` on the UTF-16 code units (not localeCompare).

const mord_messages = {
	'incorrectGroupOrder':           'Member {{name}} should be declared before all {{rank}} definitions.'
	'incorrectOrder':                'Member {{member}} should be declared before member {{beforeMember}}.'
	'incorrectRequiredMembersOrder': 'Member {{member}} should be declared after all {{optionalOrRequired}} members.'
}

const mord_default_order = ['signature', 'call-signature', 'public-static-field',
	'protected-static-field', 'private-static-field', '#private-static-field',
	'public-decorated-field', 'protected-decorated-field', 'private-decorated-field',
	'public-instance-field', 'protected-instance-field', 'private-instance-field',
	'#private-instance-field', 'public-abstract-field', 'protected-abstract-field', 'public-field',
	'protected-field', 'private-field', '#private-field', 'static-field', 'instance-field',
	'abstract-field', 'decorated-field', 'field', 'static-initialization', 'public-constructor',
	'protected-constructor', 'private-constructor', 'constructor', 'public-static-accessor',
	'protected-static-accessor', 'private-static-accessor', '#private-static-accessor',
	'public-decorated-accessor', 'protected-decorated-accessor', 'private-decorated-accessor',
	'public-instance-accessor', 'protected-instance-accessor', 'private-instance-accessor',
	'#private-instance-accessor', 'public-abstract-accessor', 'protected-abstract-accessor',
	'public-accessor', 'protected-accessor', 'private-accessor', '#private-accessor',
	'static-accessor', 'instance-accessor', 'abstract-accessor', 'decorated-accessor', 'accessor',
	'public-static-get', 'protected-static-get', 'private-static-get', '#private-static-get',
	'public-decorated-get', 'protected-decorated-get', 'private-decorated-get',
	'public-instance-get', 'protected-instance-get', 'private-instance-get',
	'#private-instance-get', 'public-abstract-get', 'protected-abstract-get', 'public-get',
	'protected-get', 'private-get', '#private-get', 'static-get', 'instance-get', 'abstract-get',
	'decorated-get', 'get', 'public-static-set', 'protected-static-set', 'private-static-set',
	'#private-static-set', 'public-decorated-set', 'protected-decorated-set',
	'private-decorated-set', 'public-instance-set', 'protected-instance-set',
	'private-instance-set', '#private-instance-set', 'public-abstract-set', 'protected-abstract-set',
	'public-set', 'protected-set', 'private-set', '#private-set', 'static-set', 'instance-set',
	'abstract-set', 'decorated-set', 'set', 'public-static-method', 'protected-static-method',
	'private-static-method', '#private-static-method', 'public-decorated-method',
	'protected-decorated-method', 'private-decorated-method', 'public-instance-method',
	'protected-instance-method', 'private-instance-method', '#private-instance-method',
	'public-abstract-method', 'protected-abstract-method', 'public-method', 'protected-method',
	'private-method', '#private-method', 'static-method', 'instance-method', 'abstract-method',
	'decorated-method', 'method']

const mord_type_items = ['readonly-signature', 'signature', 'readonly-field', 'field', 'method',
	'constructor']

const mord_orders = ['alphabetically', 'alphabetically-case-insensitive', 'as-written', 'natural',
	'natural-case-insensitive']

// mord_all_member_types ports allMemberTypes.
fn mord_all_member_types() []string {
	mut out := []string{}
	for typ in ['readonly-signature', 'signature', 'readonly-field', 'field', 'method',
		'call-signature', 'constructor', 'accessor', 'get', 'set', 'static-initialization'] {
		out << typ
		for accessibility in ['public', 'protected', 'private', '#private'] {
			if typ !in ['readonly-signature', 'signature', 'static-initialization', 'call-signature']
				&& !(typ == 'constructor' && accessibility == '#private') {
				out << '${accessibility}-${typ}'
			}
			if accessibility != '#private'
				&& typ in ['readonly-field', 'field', 'method', 'accessor', 'get', 'set'] {
				out << '${accessibility}-decorated-${typ}'
				out << 'decorated-${typ}'
			}
			if typ !in ['constructor', 'readonly-signature', 'signature', 'call-signature'] {
				mut scopes := ['static', 'instance']
				if accessibility !in ['#private', 'private'] {
					scopes << 'abstract'
				}
				for scope in scopes {
					out << '${scope}-${typ}'
					out << '${accessibility}-${scope}-${typ}'
				}
			}
		}
	}
	return out
}

// MordConfig is an OrderConfig: `never`, or the member types (each a list of one or more
// names, empty when not given or `never`), the order and the optionality order.
struct MordConfig {
	never              bool
	has_member_types   bool
	member_types       [][]string
	order              string
	optionality_order  string
}

fn mord_member_types(value json2.Any, allowed []string) ![][]string {
	if value !is []json2.Any {
		return error('member types must be a list')
	}
	mut out := [][]string{}
	for item in value.as_array() {
		match item {
			string {
				if item !in allowed {
					return error('unknown member type `${item}`')
				}
				out << [item]
			}
			[]json2.Any {
				mut group := []string{}
				for name in item {
					if name !is string || (name as string) !in allowed {
						return error('unknown member type in a group')
					}
					group << name as string
				}
				// An array of one name is still an array (`Array.isArray`).
				out << group
			}
			else {
				return error('member types must be names or lists of names')
			}
		}
	}
	return out
}

fn mord_config(value json2.Any, allowed []string) !MordConfig {
	if value is string {
		if value != 'never' {
			return error('an order config must be `never`, a list or an object')
		}
		return MordConfig{
			never: true
		}
	}
	if value is []json2.Any {
		return MordConfig{
			has_member_types: true
			member_types:     mord_member_types(value, allowed)!
		}
	}
	if value !is map[string]json2.Any {
		return error('an order config must be `never`, a list or an object')
	}
	m := value.as_map()
	mut config := MordConfig{}
	mut has_member_types := false
	mut member_types := [][]string{}
	mut order := ''
	mut optionality_order := ''
	for key, v in m {
		match key {
			'memberTypes' {
				if v is string {
					if v != 'never' {
						return error('memberTypes must be `never` or a list')
					}
				} else {
					has_member_types = true
					member_types = mord_member_types(v, allowed)!
				}
			}
			'order' {
				if v !is string || (v as string) !in mord_orders {
					return error('order must be one of ${mord_orders}')
				}
				order = v as string
			}
			'optionalityOrder' {
				if v !is string || (v as string) !in ['optional-first', 'required-first'] {
					return error('optionalityOrder must be optional-first or required-first')
				}
				optionality_order = v as string
			}
			else {
				return error('unknown key `${key}` in an order config')
			}
		}
	}
	config = MordConfig{
		has_member_types:  has_member_types
		member_types:      member_types
		order:             order
		optionality_order: optionality_order
	}
	return config
}

struct MordOptions {
	classes           ?MordConfig
	class_expressions ?MordConfig
	default_          ?MordConfig
	interfaces        ?MordConfig
	type_literals     ?MordConfig
}

fn mord_options(options []json2.Any) !MordOptions {
	o := option_object(member_ordering, options, ['classes', 'classExpressions', 'default',
		'interfaces', 'typeLiterals'])!
	all := mord_all_member_types()
	mut configs := map[string]MordConfig{}
	for key, value in o.values {
		allowed := if key in ['interfaces', 'typeLiterals'] { mord_type_items } else { all }
		configs[key] = mord_config(value, allowed) or {
			return error('`${key}` of `${member_ordering}`: ${err.msg()}')
		}
	}
	return MordOptions{
		classes:           configs['classes'] or { none }
		class_expressions: configs['classExpressions'] or { none }
		default_:          configs['default'] or { none }
		interfaces:        configs['interfaces'] or { none }
		type_literals:     configs['typeLiterals'] or { none }
	}
}

fn (mut c Checker) lint_member_ordering(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := mord_options(c.rule_options(member_ordering))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for step in t.steps() {
		if step.leave {
			continue
		}
		node := step.node
		mut members := []int{}
		mut config := ?MordConfig(none)
		mut supports_modifiers := false
		match t.typ(node) {
			.class_declaration, .class_expression {
				body := t.node(node, .body) or { continue }
				members = t.list(body, .body) or { []int{} }
				config = if t.typ(node) == .class_declaration { o.classes } else { o.class_expressions }
				supports_modifiers = true
			}
			.ts_interface_declaration {
				body := t.node(node, .body) or { continue }
				members = t.list(body, .body) or { []int{} }
				config = o.interfaces
			}
			.ts_type_literal {
				members = t.list(node, .members) or { []int{} }
				config = o.type_literals
			}
			else {
				continue
			}
		}
		stats.checked++
		chosen := config or { o.default_ or { continue } }
		c.mord_validate_members_order(t, members, chosen, supports_modifiers, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// mord_node_type ports getNodeType ('' for null).
fn mord_node_type(t &estree.EsTree, node int) string {
	readonly := t.flag(node, .readonly) or { false }
	match t.typ(node) {
		.ts_abstract_method_definition, .method_definition, .ts_method_signature {
			return t.string_of(node, .kind) or { '' }
		}
		.ts_call_signature_declaration {
			return 'call-signature'
		}
		.ts_construct_signature_declaration {
			return 'constructor'
		}
		.ts_abstract_property_definition, .ts_property_signature {
			return if readonly { 'readonly-field' } else { 'field' }
		}
		.ts_abstract_accessor_property, .accessor_property {
			return 'accessor'
		}
		.property_definition {
			value := t.node(node, .value) or { -1 }
			if value >= 0 && t.typ(value) in [.function_expression, .arrow_function_expression] {
				return 'method'
			}
			return if readonly { 'readonly-field' } else { 'field' }
		}
		.ts_index_signature {
			return if readonly { 'readonly-signature' } else { 'signature' }
		}
		.static_block {
			return 'static-initialization'
		}
		else {
			return ''
		}
	}
}

// mord_member_raw_name ports getMemberRawName.
fn (c &Checker) mord_member_raw_name(t &estree.EsTree, node int) string {
	name, typ := c.tsm_name_from_member(t, node)
	if typ == .quoted {
		return name[1..name.len - 1]
	}
	if typ == .private_ {
		return name[1..]
	}
	return name
}

// mord_member_name ports getMemberName (none for null).
fn (c &Checker) mord_member_name(t &estree.EsTree, node int) ?string {
	match t.typ(node) {
		.ts_property_signature, .ts_method_signature, .ts_abstract_accessor_property,
		.ts_abstract_property_definition, .accessor_property, .property_definition {
			return c.mord_member_raw_name(t, node)
		}
		.ts_abstract_method_definition, .method_definition {
			if (t.string_of(node, .kind) or { '' }) == 'constructor' {
				return 'constructor'
			}
			return c.mord_member_raw_name(t, node)
		}
		.ts_construct_signature_declaration {
			return 'new'
		}
		.ts_call_signature_declaration {
			return 'call'
		}
		.ts_index_signature {
			// getNameFromIndexSignature
			for parameter in t.list(node, .parameters) or { []int{} } {
				if t.typ(parameter) == .identifier {
					return t.string_of(parameter, .name) or { '' }
				}
			}
			return '(index signature)'
		}
		.static_block {
			return 'static block'
		}
		else {
			return none
		}
	}
}

// mord_is_member_optional ports isMemberOptional.
fn mord_is_member_optional(t &estree.EsTree, node int) bool {
	if t.typ(node) in [.ts_property_signature, .ts_method_signature, .ts_abstract_accessor_property,
		.ts_abstract_property_definition, .accessor_property, .property_definition,
		.ts_abstract_method_definition, .method_definition] {
		return t.flag(node, .optional) or { false }
	}
	return false
}

// mord_member_initializer ports getMemberInitializer (-1 for none).
fn mord_member_initializer(t &estree.EsTree, node int) int {
	if t.typ(node) in [.accessor_property, .property_definition] {
		return t.node(node, .value) or { -1 }
	}
	return -1
}

// mord_is_evaluated_later ports isEvaluatedLater.
fn mord_is_evaluated_later(t &estree.EsTree, node int, initializer int) bool {
	stop := t.nodes[initializer].parent
	mut current := node
	for current >= 0 && current != stop {
		if t.typ(current) in [.arrow_function_expression, .class_body, .function_expression] {
			return true
		}
		current = t.nodes[current].parent
	}
	return false
}

// mord_immediate_this_property_names ports collectImmediateThisPropertyNames.
fn mord_immediate_this_property_names(t &estree.EsTree, initializer int) []string {
	mut names := []string{}
	mut stack := [initializer]
	for stack.len > 0 {
		node := stack.pop()
		if t.typ(node) == .member_expression
			&& t.typ(t.node(node, .object) or { -1 }) == .this_expression
			&& !mord_is_evaluated_later(t, node, initializer) {
			property := t.node(node, .property) or { -1 }
			name := if t.flag(node, .computed) or { false } {
				es_tree_static_string_value(t, property)
			} else {
				t.string_of(property, .name)
			}
			if n := name {
				names << n
			}
		}
		stack << t.children(node)
	}
	return names
}

// mord_is_blocked_by_earlier_member_references ports isBlockedByEarlierMemberReferences.
fn (c &Checker) mord_is_blocked_by_earlier_member_references(t &estree.EsTree, member int, members []int, from int, to int) bool {
	initializer := mord_member_initializer(t, member)
	if initializer < 0 {
		return false
	}
	referenced := mord_immediate_this_property_names(t, initializer)
	for other in members[from..to] {
		other_name := c.mord_member_name(t, other) or { continue }
		if mord_member_initializer(t, other) >= 0 && other_name in referenced {
			return true
		}
	}
	return false
}

// mord_rank_order ports getRankOrder.
fn mord_rank_order(member_groups []string, order [][]string) int {
	for group in member_groups {
		for i, member_type in order {
			if group in member_type {
				return i
			}
		}
	}
	return -1
}

// mord_accessibility ports getAccessibility.
fn mord_accessibility(t &estree.EsTree, node int) string {
	accessibility := t.string_of(node, .accessibility) or { '' }
	if accessibility != '' {
		return accessibility
	}
	if key := t.node(node, .key) {
		if t.typ(key) == .private_identifier {
			return '#private'
		}
	}
	return 'public'
}

// mord_rank ports getRank.
fn mord_rank(t &estree.EsTree, node int, order [][]string, supports_modifiers bool) int {
	typ := mord_node_type(t, node)
	if t.typ(node) == .method_definition {
		value := t.node(node, .value) or { -1 }
		if value >= 0 && t.typ(value) == .ts_empty_body_function_expression {
			return -1
		}
	}
	if typ == '' {
		return order.len - 1
	}
	abstract := t.typ(node) in [.ts_abstract_accessor_property, .ts_abstract_property_definition,
		.ts_abstract_method_definition]
	scope := if t.flag(node, .static_) or { false } {
		'static'
	} else if abstract {
		'abstract'
	} else {
		'instance'
	}
	accessibility := mord_accessibility(t, node)
	mut groups := []string{}
	if supports_modifiers {
		decorated := (t.list(node, .decorators) or { []int{} }).len > 0
		if decorated && typ in ['readonly-field', 'field', 'method', 'accessor', 'get', 'set'] {
			groups << '${accessibility}-decorated-${typ}'
			groups << 'decorated-${typ}'
			if typ == 'readonly-field' {
				groups << '${accessibility}-decorated-field'
				groups << 'decorated-field'
			}
		}
		if typ !in ['readonly-signature', 'signature', 'static-initialization'] {
			if typ != 'constructor' {
				// Constructors have no scope
				groups << '${accessibility}-${scope}-${typ}'
				groups << '${scope}-${typ}'
				if typ == 'readonly-field' {
					groups << '${accessibility}-${scope}-field'
					groups << '${scope}-field'
				}
			}
			groups << '${accessibility}-${typ}'
			if typ == 'readonly-field' {
				groups << '${accessibility}-field'
			}
		}
	}
	groups << typ
	if typ == 'readonly-signature' {
		groups << 'signature'
	} else if typ == 'readonly-field' {
		groups << 'field'
	}
	return mord_rank_order(groups, order)
}

// mord_group_members_by_type ports groupMembersByType (which leaves out the last member).
fn mord_group_members_by_type(t &estree.EsTree, members []int, order [][]string, supports_modifiers bool) [][]int {
	mut grouped := [][]int{}
	ranks := members.map(mord_rank(t, it, order, supports_modifiers))
	mut previous_rank := ?int(none)
	for index, member in members {
		if index == members.len - 1 {
			break
		}
		rank := ranks[index]
		if previous := previous_rank {
			if rank == previous {
				if grouped.len > 0 {
					grouped[grouped.len - 1] << member
				}
				continue
			}
		}
		if rank == ranks[index + 1] {
			grouped << [member]
			previous_rank = rank
		}
	}
	return grouped
}

// mord_lowest_rank ports getLowestRank.
fn mord_lowest_rank(ranks []int, target int, order [][]string) string {
	mut lowest := ranks.last()
	for rank in ranks {
		if rank > target && rank < lowest {
			lowest = rank
		}
	}
	return order[lowest].map(it.replace('-', ' ')).join(', ')
}

// mord_check_group_sort ports checkGroupSort: none when a group is out of order.
fn (c &Checker) mord_check_group_sort(t &estree.EsTree, members []int, order [][]string, supports_modifiers bool, mut findings []Finding) ?[][]int {
	mut previous_ranks := []int{}
	mut groups := [][]int{}
	mut correct := true
	for member in members {
		rank := mord_rank(t, member, order, supports_modifiers)
		name := c.mord_member_name(t, member) or { 'null' }
		if rank == -1 {
			continue
		}
		if previous_ranks.len > 0 && rank < previous_ranks.last() {
			findings << Finding{
				stmt:       c.es_tree_position(t, member)
				message_id: 'incorrectGroupOrder'
				data:       {
					'name': name
					'rank': mord_lowest_rank(previous_ranks, rank, order)
				}
			}
			correct = false
		} else if previous_ranks.len > 0 && rank == previous_ranks.last() {
			groups[groups.len - 1] << member
		} else {
			previous_ranks << rank
			groups << [member]
		}
	}
	return if correct { groups } else { none }
}

// mord_check_alpha_sort ports checkAlphaSort.
fn (c &Checker) mord_check_alpha_sort(t &estree.EsTree, members []int, order string, mut findings []Finding) bool {
	mut previous_name := ''
	mut previous_index := 0
	mut correct := true
	for index, member in members {
		name := c.mord_member_name(t, member) or { '' }
		// Note: Not all members have names
		if name == '' {
			continue
		}
		if mord_natural_out_of_order(name, previous_name, order) {
			if c.mord_is_blocked_by_earlier_member_references(t, member, members, previous_index,
				index) {
				continue
			}
			findings << Finding{
				stmt:       c.es_tree_position(t, member)
				message_id: 'incorrectOrder'
				data:       {
					'beforeMember': previous_name
					'member':       name
				}
			}
			correct = false
		}
		previous_name = name
		previous_index = index
	}
	return correct
}

// mord_units_less is JavaScript's `<` on strings (UTF-16 code units).
fn mord_units_less(a []u16, b []u16) bool {
	for i in 0 .. if a.len < b.len { a.len } else { b.len } {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return a.len < b.len
}

// mord_natural_out_of_order ports naturalOutOfOrder.
fn mord_natural_out_of_order(name string, previous_name string, order string) bool {
	if name == previous_name {
		return false
	}
	a := utf16_units(name)
	b := utf16_units(previous_name)
	return match order {
		'alphabetically' {
			mord_units_less(a, b)
		}
		'alphabetically-case-insensitive' {
			mord_units_less(jsregexp.js_to_lower(a), jsregexp.js_to_lower(b))
		}
		'natural' {
			mord_natural_compare(a, b) != 1
		}
		'natural-case-insensitive' {
			mord_natural_compare(jsregexp.js_to_lower(a), jsregexp.js_to_lower(b)) != 1
		}
		else {
			false
		}
	}
}

// mord_natural_code is getCode(str, pos) of natural-compare 1.4.0 (without String.alphabet).
fn mord_natural_code(s []u16, pos int) int {
	code := if pos >= 0 && pos < s.len { int(s[pos]) } else { 0 }
	return if code < 45 || code > 127 {
		code
	} else if code < 46 {
		65 // -
	} else if code < 48 {
		code - 1
	} else if code < 58 {
		code + 18 // 0-9
	} else if code < 65 {
		code - 11
	} else if code < 91 {
		code + 11 // A-Z
	} else if code < 97 {
		code - 37
	} else if code < 123 {
		code + 5 // a-z
	} else {
		code - 63
	}
}

// mord_natural_number is getCode(str, pos, code) with a code: the number of the digits from
// pos - 1, and where they end.
fn mord_natural_number(s []u16, pos int) (f64, int) {
	mut i := pos
	for {
		code := mord_natural_code(s, i)
		if !(code < 76 && code > 65) {
			break
		}
		i++
	}
	start := if pos - 1 < 0 { 0 } else { pos - 1 }
	end := if i > s.len { s.len } else { i }
	digits := if start < end { s[start..end].map(u8(it)).bytestr() } else { '' }
	// `+str.slice(pos - 1, i)`: the digits are ASCII
	return estree.js_parse_float(if digits == '' { '0' } else { digits }), i
}

// mord_natural_compare ports naturalCompare of natural-compare 1.4.0 on UTF-16 code units.
fn mord_natural_compare(a []u16, b []u16) int {
	if a == b {
		return 0
	}
	mut pos_a := 0
	mut pos_b := 0
	mut code_b := f64(1)
	for code_b != 0 {
		mut code_a := f64(mord_natural_code(a, pos_a))
		pos_a++
		code_b = f64(mord_natural_code(b, pos_b))
		pos_b++
		if code_a < 76 && code_b < 76 && code_a > 66 && code_b > 66 {
			number_a, i_a := mord_natural_number(a, pos_a)
			code_a = number_a
			pos_a = i_a
			number_b, i_b := mord_natural_number(b, pos_b)
			code_b = number_b
			pos_b = i_b
		}
		if code_a != code_b {
			return if code_a < code_b { -1 } else { 1 }
		}
	}
	return 0
}

// mord_check_required_order ports checkRequiredOrder.
fn (c &Checker) mord_check_required_order(t &estree.EsTree, members []int, optionality_order string, mut findings []Finding) bool {
	mut switch_index := -1
	for i in 1 .. members.len {
		if mord_is_member_optional(t, members[i]) != mord_is_member_optional(t, members[i - 1]) {
			switch_index = i
			break
		}
	}
	report := fn [c, t, optionality_order] (member int) Finding {
		return Finding{
			stmt:       c.es_tree_position(t, member)
			message_id: 'incorrectRequiredMembersOrder'
			data:       {
				'member':             c.mord_member_name(t, member) or { 'null' }
				'optionalOrRequired': if optionality_order == 'required-first' {
					'required'
				} else {
					'optional'
				}
			}
		}
	}
	if mord_is_member_optional(t, members[0]) != (optionality_order == 'optional-first') {
		findings << report(members[0])
		return false
	}
	for i in switch_index + 1 .. members.len {
		if mord_is_member_optional(t, members[i]) != mord_is_member_optional(t, members[switch_index]) {
			findings << report(members[switch_index])
			return false
		}
	}
	return true
}

// mord_check_order is checkOrder of validateMembersOrder (`all` its members).
fn (c &Checker) mord_check_order(t &estree.EsTree, member_set []int, all []int, config MordConfig, supports_modifiers bool, mut findings []Finding) {
	has_alpha_sort := config.order != '' && config.order != 'as-written'
	if config.has_member_types {
		grouped := c.mord_check_group_sort(t, member_set, config.member_types, supports_modifiers, mut
			findings) or {
			// checkAlphaSortForAllMembers, with all the members.
			if has_alpha_sort {
				for group in mord_group_members_by_type(t, all, config.member_types, supports_modifiers) {
					c.mord_check_alpha_sort(t, group, config.order, mut findings)
				}
			}
			return
		}
		if has_alpha_sort {
			for group in grouped {
				c.mord_check_alpha_sort(t, group, config.order, mut findings)
			}
		}
	} else if has_alpha_sort {
		c.mord_check_alpha_sort(t, member_set, config.order, mut findings)
	}
}

// mord_validate_members_order ports validateMembersOrder.
fn (c &Checker) mord_validate_members_order(t &estree.EsTree, members []int, config MordConfig, supports_modifiers bool, mut findings []Finding) {
	if config.never {
		return
	}
	if config.optionality_order == '' {
		c.mord_check_order(t, members, members, config, supports_modifiers, mut findings)
		return
	}
	mut switch_index := -1
	for i in 1 .. members.len {
		if mord_is_member_optional(t, members[i]) != mord_is_member_optional(t, members[i - 1]) {
			switch_index = i
			break
		}
	}
	if switch_index != -1 {
		if !c.mord_check_required_order(t, members, config.optionality_order, mut findings) {
			return
		}
		c.mord_check_order(t, members[..switch_index], members, config, supports_modifiers, mut
			findings)
		c.mord_check_order(t, members[switch_index..], members, config, supports_modifiers, mut
			findings)
	} else {
		c.mord_check_order(t, members, members, config, supports_modifiers, mut findings)
	}
}
