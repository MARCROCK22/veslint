module rules

import json2
import time
import treesitter { named_children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `prefer-const` rule of ESLint 10.6.0.

const pconst_messages = {
	'useConst': "'{{name}}' is never reassigned. Use 'const' instead."
}

struct PconstOptions {
	all                       bool // destructuring: "all"
	ignore_read_before_assign bool
}

fn pconst_options(options []json2.Any) !PconstOptions {
	o := option_object(prefer_const, options, ['destructuring', 'ignoreReadBeforeAssign'])!
	destructuring := o.string_value('destructuring', ['any', 'all'])!
	return PconstOptions{
		all:                       destructuring == 'all'
		ignore_read_before_assign: o.bool_value('ignoreReadBeforeAssign') or { false }
	}
}

// PconstDeclaration is an ESTree VariableDeclaration: a `lexical_declaration` or, for
// `for (let a of b)`, the for-in/of statement, whose `left` is the only declarator (without init).
struct PconstDeclaration {
	node     C.TSNode
	for_in   bool
	start    int
	end      int
	kind_tok C.TSNode
}

// PconstDeclarator is a VariableDeclarator: its id and init.
struct PconstDeclarator {
	id   C.TSNode
	init ?C.TSNode
}

struct PconstState {
mut:
	checked_name ?string = ''
	checked_id   u64     = u64(0xffffffffffffffff)
	report_count int
}

fn (mut c Checker) lint_prefer_const(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := pconst_options(c.rule_options(prefer_const))!
	tree := c.scope_tree(root)
	// The variables of the `let` declarations (not in the init of a `for`), in the order of the
	// declarations and, in each one, of the definitions.
	mut variables := []int{}
	mut starts := map[int]int{}
	for v, variable in tree.variables {
		if variable.defs.len == 0 {
			continue
		}
		def := variable.defs[0]
		if def.kind != .variable || def.parent_kind != 'let' {
			continue
		}
		declaration := es_def_parent(def) or { continue }
		if node_kind(declaration) == 'lexical_declaration' {
			if parent := node_parent(declaration) {
				if node_kind(parent) == 'for_statement' {
					if body := node_field(parent, 'body') {
						if node_key(body) != node_key(declaration) {
							continue
						}
					}
				}
			}
		}
		stats.checked++
		variables << v
		starts[v] = node_start(declaration)
	}
	variables.sort_with_compare(fn [starts, tree] (a &int, b &int) int {
		if starts[*a] != starts[*b] {
			return if starts[*a] < starts[*b] { -1 } else { 1 }
		}
		x := node_start(tree.variables[*a].defs[0].name)
		y := node_start(tree.variables[*b].defs[0].name)
		return if x < y {
			-1
		} else if x > y {
			1
		} else {
			0
		}
	})
	// groupByDestructuring
	mut groups := map[string][]?C.TSNode{}
	mut group_order := []string{}
	for v in variables {
		identifier := c.pconst_identifier(tree, v, o.ignore_read_before_assign)
		mut previous := u64(0xffffffffffffffff)
		for r in tree.variables[v].references {
			id := tree.references[r].identifier
			if node_key(id) == previous {
				continue
			}
			previous = node_key(id)
			host := pconst_destructuring_host(tree, r) or { continue }
			key := '${node_start(host)}-${node_end(host)}-${node_kind(host)}'
			if key !in groups {
				group_order << key
				groups[key] = []?C.TSNode{}
			}
			groups[key] << identifier
		}
	}
	mut findings := []Finding{}
	mut st := PconstState{}
	for key in group_order {
		c.pconst_check_group(groups[key], o, mut st, mut findings)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// pconst_skip_patterns walks up from a node past the patterns (PATTERN_TYPE) and parentheses: the
// first other ancestor, with the child it was reached from.
fn pconst_skip_patterns(n C.TSNode) ?(C.TSNode, C.TSNode) {
	mut child := n
	mut node := node_parent(n)?
	for node_kind(node) in ['object_pattern', 'array_pattern', 'pair_pattern',
		'object_assignment_pattern', 'assignment_pattern', 'rest_pattern', 'parenthesized_expression'] {
		child = node
		node = node_parent(node)?
	}
	return node, child
}

// pconst_is_declarator: the node reached from `child` is a VariableDeclarator (the left of a
// for-in/of that declares it is one in ESTree).
fn pconst_is_declarator(node C.TSNode, child C.TSNode) bool {
	if node_kind(node) == 'variable_declarator' {
		return true
	}
	if node_kind(node) == 'for_in_statement' {
		if _ := node_field(node, 'kind') {
			left := node_field(node, 'left') or { return false }
			return node_key(left) == node_key(child)
		}
	}
	return false
}

// pconst_destructuring_host ports getDestructuringHost: the declarator or assignment a write is
// the target of.
fn pconst_destructuring_host(tree &ScopeTree, r int) ?C.TSNode {
	reference := tree.references[r]
	if !reference.write {
		return none
	}
	node, child := pconst_skip_patterns(reference.identifier)?
	if pconst_is_declarator(node, child)
		|| node_kind(node) in ['assignment_expression', 'augmented_assignment_expression'] {
		return node
	}
	return none
}

// pconst_can_become_declaration ports canBecomeVariableDeclaration.
fn pconst_can_become_declaration(identifier C.TSNode) bool {
	node, child := pconst_skip_patterns(identifier) or { return false }
	if pconst_is_declarator(node, child) {
		return true
	}
	if node_kind(node) !in ['assignment_expression', 'augmented_assignment_expression'] {
		return false
	}
	mut statement := node_parent(node) or { return false }
	for node_kind(statement) == 'parenthesized_expression' {
		statement = node_parent(statement) or { return false }
	}
	if node_kind(statement) != 'expression_statement' {
		return false
	}
	host := node_parent(statement) or { return false }
	return match node_kind(host) {
		'program', 'switch_case', 'switch_default' { true }
		'statement_block' {
			node_kind(node_parent(host) or { host }) !in ['internal_module', 'module',
				'ambient_declaration']
		}
		else { false }
	}
}

// pconst_has_member_assignment ports hasMemberExpressionAssignment.
fn pconst_has_member_assignment(n C.TSNode) bool {
	node := unwrap_parens(n)
	match node_kind(node) {
		'object_pattern' {
			for prop in named_children(node) {
				match node_kind(prop) {
					'pair_pattern' {
						value := node_field(prop, 'value') or { continue }
						if pconst_has_member_assignment(value) {
							return true
						}
					}
					'rest_pattern' {
						argument := named_children(prop).filter(node_kind(it) != 'comment')[0] or {
							continue
						}
						if pconst_has_member_assignment(argument) {
							return true
						}
					}
					else {}
				}
			}
		}
		'array_pattern' {
			for element in named_children(node) {
				if node_kind(element) != 'comment' && pconst_has_member_assignment(element) {
					return true
				}
			}
		}
		'assignment_pattern' {
			left := node_field(node, 'left') or { return false }
			return pconst_has_member_assignment(left)
		}
		'member_expression', 'subscript_expression' {
			return true
		}
		else {}
	}
	return false
}

// pconst_is_outer_variable ports isOuterVariableInDestructing.
fn (c &Checker) pconst_is_outer_variable(tree &ScopeTree, name ?string, scope int) bool {
	n := name or { return false }
	for r in tree.scopes[scope].through {
		resolved := tree.references[r].resolved
		if resolved >= 0 && tree.variables[resolved].name == n {
			return true
		}
	}
	v := tree.find_variable(scope, n, -1)
	if v < 0 {
		return false
	}
	return tree.variables[v].defs.any(it.kind == .parameter)
}

// pconst_identifier ports getIdentifierIfShouldBeConst.
fn (c &Checker) pconst_identifier(tree &ScopeTree, v int, ignore_read_before_assign bool) ?C.TSNode {
	variable := tree.variables[v]
	if variable.eslint_used && tree.scopes[variable.scope].kind == .global {
		return none
	}
	mut writer := -1
	mut read_before_init := false
	for r in variable.references {
		reference := tree.references[r]
		if reference.write {
			if writer >= 0 && node_key(tree.references[writer].identifier) != node_key(reference.identifier) {
				return none
			}
			if host := pconst_destructuring_host(tree, r) {
				if node_kind(host) in ['assignment_expression', 'augmented_assignment_expression'] {
					left := unwrap_parens(node_field(host, 'left') or { host })
					mut outer := false
					mut non_identifiers := false
					if node_kind(left) == 'object_pattern' {
						for prop in named_children(left) {
							// Properties with a `value`: its name when it is an identifier.
							name := match node_kind(prop) {
								'shorthand_property_identifier_pattern' {
									?string(c.identifier_name(prop))
								}
								'pair_pattern' {
									value := unwrap_parens(node_field(prop, 'value') or { continue })
									if node_kind(value) in ['identifier', 'undefined'] {
										?string(c.identifier_name(value))
									} else {
										?string(none)
									}
								}
								'object_assignment_pattern' {
									?string(none)
								}
								else {
									continue
								}
							}
							if c.pconst_is_outer_variable(tree, name, variable.scope) {
								outer = true
								break
							}
						}
						non_identifiers = pconst_has_member_assignment(left)
					} else if node_kind(left) == 'array_pattern' {
						for element in named_children(left) {
							if node_kind(element) == 'comment' {
								continue
							}
							e := unwrap_parens(element)
							name := if node_kind(e) in ['identifier', 'undefined'] {
								?string(c.identifier_name(e))
							} else {
								?string(none)
							}
							if c.pconst_is_outer_variable(tree, name, variable.scope) {
								outer = true
								break
							}
						}
						non_identifiers = pconst_has_member_assignment(left)
					}
					if outer || non_identifiers {
						return none
					}
				}
			}
			writer = r
		} else if reference.read && writer < 0 {
			if ignore_read_before_assign {
				return none
			}
			read_before_init = true
		}
	}
	if writer < 0 || tree.references[writer].from != variable.scope
		|| !pconst_can_become_declaration(tree.references[writer].identifier) {
		return none
	}
	if read_before_init {
		return variable.defs[0].name
	}
	return tree.references[writer].identifier
}

// pconst_declaration_of ports findUp(node, "VariableDeclaration", a statement stops it).
fn pconst_declaration_of(n C.TSNode) ?PconstDeclaration {
	mut node := n
	mut child := n
	for {
		kind := node_kind(node)
		if kind == 'for_in_statement' {
			// The declaration of `for (let a of b)` is in the for-in/of.
			kind_tok := node_field(node, 'kind') or { return none }
			left := node_field(node, 'left') or { return none }
			if node_key(left) != node_key(child) {
				return none
			}
			return PconstDeclaration{
				node:     node
				for_in:   true
				start:    node_start(kind_tok)
				end:      node_end(left)
				kind_tok: kind_tok
			}
		}
		if kind.ends_with('_statement') || kind == 'statement_block' {
			return none
		}
		if kind in ['lexical_declaration', 'variable_declaration'] {
			kind_tok := node_field(node, 'kind') or {
				named_children(node)[0] or { return none }
			}
			mut start := node_start(node)
			if parent := node_parent(node) {
				if node_kind(parent) == 'ambient_declaration' {
					start = node_start(parent)
				}
			}
			return PconstDeclaration{
				node:     node
				start:    start
				end:      node_end(node)
				kind_tok: kind_tok
			}
		}
		child = node
		node = node_parent(node) or { return none }
	}
	return none
}

fn pconst_declarators(d PconstDeclaration) []PconstDeclarator {
	if d.for_in {
		left := node_field(d.node, 'left') or { return [] }
		return [PconstDeclarator{
			id: left
		}]
	}
	mut out := []PconstDeclarator{}
	for declarator in named_children(d.node) {
		if node_kind(declarator) == 'variable_declarator' {
			out << PconstDeclarator{
				id:   node_field(declarator, 'name') or { continue }
				init: node_field(declarator, 'value')
			}
		}
	}
	return out
}

// pconst_check_group ports checkGroup.
fn (c &Checker) pconst_check_group(nodes []?C.TSNode, o PconstOptions, mut st PconstState, mut findings []Finding) {
	mut to_report := []C.TSNode{}
	for n in nodes {
		if node := n {
			to_report << node
		}
	}
	if nodes.len == 0 || (o.all && to_report.len != nodes.len) {
		return
	}
	mut declaration := ?PconstDeclaration(none)
	if first := nodes[0] {
		declaration = pconst_declaration_of(first)
	}
	mut should_fix := false
	if d := declaration {
		declarators := pconst_declarators(d)
		if declarators.len > 0 {
			first := declarators[0]
			if init := first.init {
				// The name or id of the first declarator: when it changes, the count starts again.
				id_name := if node_kind(first.id) in ['identifier', 'undefined'] {
					?string(c.identifier_name(first.id))
				} else {
					?string(none)
				}
				if !pconst_same_name(id_name, st.checked_name) {
					st.checked_name = id_name
					st.report_count = 0
				}
				if node_kind(first.id) == 'object_pattern' {
					value := unwrap_parens(init)
					init_name := if node_kind(value) in ['identifier', 'undefined'] {
						?string(c.identifier_name(value))
					} else {
						?string(none)
					}
					if !pconst_same_name(init_name, st.checked_name) {
						st.checked_name = init_name
						st.report_count = 0
					}
				}
				if node_key(first.id) != st.checked_id {
					st.checked_id = node_key(first.id)
					st.report_count = 0
				}
			}
		}
		should_fix = (d.for_in || declarators.all(it.init != none)) && to_report.len == nodes.len
		if declarators.len != 1 && declarators.len >= 1 {
			st.report_count += to_report.len
			mut total := 0
			for declarator in declarators {
				total += match node_kind(declarator.id) {
					'object_pattern', 'array_pattern' {
						pconst_pattern_length(declarator.id)
					}
					else {
						1
					}
				}
			}
			should_fix = should_fix && st.report_count == total
		}
	}
	for node in to_report {
		mut fix := Fix{}
		if should_fix {
			d := declaration or { PconstDeclaration{} }
			end := c.tokens.last_end(d.end)
			fix = Fix{d.start, end, c.src[d.start..node_start(d.kind_tok)] + 'const' +
				c.src[node_end(d.kind_tok)..end]}
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'useConst'
			data:       {
				'name': c.identifier_name(node)
			}
			has_fix:    should_fix
			fix:        fix
		}
	}
}

fn pconst_same_name(a ?string, b ?string) bool {
	x := a or { return b == none }
	y := b or { return false }
	return x == y
}

// pconst_pattern_length is `properties.length` of an object pattern or `elements.length` of an
// array pattern (holes included).
fn pconst_pattern_length(n C.TSNode) int {
	if node_kind(n) == 'object_pattern' {
		return named_children(n).filter(node_kind(it) != 'comment').len
	}
	return es_array_elements(n).len
}
