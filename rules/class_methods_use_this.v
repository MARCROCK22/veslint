module rules

import estree
import json2
import time
import treesitter { Ident }

// Port of the `@typescript-eslint/class-methods-use-this` rule of typescript-eslint 8.72.2 (which
// extends ESLint's rule of the same name), with all its options.

const cmut_messages = {
	'missingThis': "Expected 'this' to be used by class {{name}}."
}

struct CmutOptions {
	enforce_for_class_fields bool
	except_methods           []string
	// ignoreClassesThatImplementAnInterface: '' (false), 'true' or 'public-fields'.
	ignore_implementing     string
	ignore_override_methods bool
}

fn cmut_options(options []json2.Any) !CmutOptions {
	o := option_object(class_methods_use_this, options, ['enforceForClassFields', 'exceptMethods',
		'ignoreClassesThatImplementAnInterface', 'ignoreOverrideMethods'])!
	mut ignore_implementing := ''
	if value := o.values['ignoreClassesThatImplementAnInterface'] {
		if value is bool {
			ignore_implementing = if value { 'true' } else { '' }
		} else if value is string {
			ignore_implementing = value
		}
	}
	return CmutOptions{
		enforce_for_class_fields: o.bool_value('enforceForClassFields') or { true }
		except_methods:           o.string_list('exceptMethods') or { []string{} }
		ignore_implementing:      ignore_implementing
		ignore_override_methods:  o.bool_value('ignoreOverrideMethods') or { false }
	}
}

// CmutFrame is an entry of the rule's stack: the class member of a function (-1 for a context
// that is not one), and whether `this` or `super` was used in it.
struct CmutFrame {
	class  int
	member int
mut:
	uses_this bool
}

fn (mut c Checker) lint_class_methods_use_this(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := cmut_options(c.rule_options(class_methods_use_this))!
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut stack := []CmutFrame{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		parent := t.nodes[node].parent
		parent_typ := if parent >= 0 { t.typ(parent) } else { estree.NodeType.program }
		// `PropertyDefinition > ArrowFunctionExpression.value` (and AccessorProperty's).
		is_field_arrow := o.enforce_for_class_fields && typ == .arrow_function_expression
			&& parent_typ in [.property_definition, .accessor_property]
			&& (t.node(parent, .value) or { -1 }) == node
		if !step.leave {
			match typ {
				.function_declaration, .static_block {
					stack << CmutFrame{
						class:  -1
						member: -1
					}
				}
				.this_expression, .super {
					if stack.len > 0 {
						stack[stack.len - 1].uses_this = true
					}
				}
				else {}
			}
			if typ == .function_expression || is_field_arrow {
				stack << cmut_enter_function(t, node)
			}
			continue
		}
		match typ {
			.function_declaration, .static_block, .property_definition, .accessor_property {
				if stack.len > 0 {
					stack.delete_last()
				}
			}
			else {}
		}
		if typ == .function_expression || is_field_arrow {
			stats.checked++
			if stack.len == 0 {
				continue
			}
			frame := stack.pop()
			if f := c.cmut_exit_function(t, o, frame, node) {
				findings << f
			}
		}
		// `PropertyDefinition > *.key:exit` (and AccessorProperty's): a context for the value.
		if parent_typ in [.property_definition, .accessor_property]
			&& (t.node(parent, .key) or { -1 }) == node {
			stack << CmutFrame{
				class:  -1
				member: -1
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// cmut_enter_function ports enterFunction and pushContext: a member's function has a context of
// the member and its class.
fn cmut_enter_function(t &estree.EsTree, node int) CmutFrame {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) in [.method_definition, .property_definition, .accessor_property] {
		body := t.nodes[parent].parent
		if body >= 0 && t.typ(body) == .class_body {
			return CmutFrame{
				class:  t.nodes[body].parent
				member: parent
			}
		}
	}
	return CmutFrame{
		class:  -1
		member: -1
	}
}

// cmut_is_included_instance_method ports isIncludedInstanceMethod.
fn cmut_is_included_instance_method(t &estree.EsTree, o CmutOptions, member int) bool {
	if (t.flag(member, .static_) or { false })
		|| (t.typ(member) == .method_definition && (t.string_of(member, .kind) or { '' }) == 'constructor')
		|| (t.typ(member) in [.property_definition, .accessor_property] && !o.enforce_for_class_fields) {
		return false
	}
	if (t.flag(member, .computed) or { false }) || o.except_methods.len == 0 {
		return true
	}
	key := t.node(member, .key) or { return true }
	hash := if t.typ(key) == .private_identifier { '#' } else { '' }
	// getStaticMemberAccessValue of a key that is not computed: its name, or its literal's value.
	name := if t.typ(key) in [.identifier, .private_identifier] {
		t.string_of(key, .name) or { return true }
	} else {
		es_tree_static_string_value(t, key) or { return true }
	}
	return hash + name !in o.except_methods
}

// cmut_exit_function ports exitFunction.
fn (mut c Checker) cmut_exit_function(t &estree.EsTree, o CmutOptions, frame CmutFrame, node int) ?Finding {
	if frame.member < 0 || frame.uses_this {
		return none
	}
	member := frame.member
	if o.ignore_override_methods && (t.flag(member, .override) or { false }) {
		return none
	}
	implements := t.list(frame.class, .implements_) or { []int{} }
	if o.ignore_implementing == 'true' && implements.len > 0 {
		return none
	}
	if o.ignore_implementing == 'public-fields' && implements.len > 0 {
		accessibility := t.string_of(member, .accessibility) or { '' }
		if accessibility in ['', 'public'] {
			return none
		}
	}
	if !cmut_is_included_instance_method(t, o, member) {
		return none
	}
	return Finding{
		stmt:       c.cmut_function_head(t, node)
		message_id: 'missingThis'
		data:       {
			'name': c.cmut_function_name(t, node)
		}
	}
}

// cmut_function_head ports getFunctionHeadLoc of typescript-eslint's util: as ESLint's, but a class
// member's head starts after its decorators.
fn (mut c Checker) cmut_function_head(t &estree.EsTree, node int) Ident {
	parent := t.nodes[node].parent
	if parent >= 0 && t.typ(parent) in [.method_definition, .property_definition] {
		mut start := t.nodes[parent].start
		decorators := t.list(parent, .decorators) or { []int{} }
		if decorators.len > 0 {
			tokens := c.source_tokens(t.nodes[t.root].ts)
			if token := tokens.after(t.nodes[decorators.last()].end, false) {
				start = token.start
			}
		}
		return c.position_range(start, c.es_tree_params_paren(t, node))
	}
	if parent >= 0 && t.typ(parent) == .property {
		return c.position_range(t.nodes[parent].start, c.es_tree_params_paren(t, node))
	}
	if t.typ(node) == .arrow_function_expression {
		return c.es_tree_function_head(t, node)
	}
	return c.position_range(t.nodes[node].start, c.es_tree_params_paren(t, node))
}

// cmut_function_name ports getFunctionNameWithKind of @eslint-community/eslint-utils, which
// typescript-eslint calls without `sourceCode`: a computed key that is not a constant gets no name.
fn (mut c Checker) cmut_function_name(t &estree.EsTree, node int) string {
	parent := t.nodes[node].parent
	if parent < 0 {
		return ''
	}
	ptyp := t.typ(parent)
	is_value := (t.node(parent, .value) or { -1 }) == node
	is_object_method := ptyp == .property && is_value
	is_class_method := ptyp == .method_definition && is_value
	is_class_field_method := ptyp == .property_definition && is_value
	mut tokens := []string{}
	key := if is_object_method || is_class_method || is_class_field_method {
		t.node(parent, .key) or { -1 }
	} else {
		-1
	}
	if is_class_method || is_class_field_method {
		if t.flag(parent, .static_) or { false } {
			tokens << 'static'
		}
		if key >= 0 && t.typ(key) == .private_identifier {
			tokens << 'private'
		}
	}
	if t.flag(node, .async) or { false } {
		tokens << 'async'
	}
	if t.flag(node, .generator) or { false } {
		tokens << 'generator'
	}
	if is_object_method || is_class_method {
		kind := t.string_of(parent, .kind) or { '' }
		if kind == 'constructor' {
			return 'constructor'
		}
		tokens << match kind {
			'get' { 'getter' }
			'set' { 'setter' }
			else { 'method' }
		}
	} else if is_class_field_method {
		tokens << 'method'
	} else {
		if t.typ(node) == .arrow_function_expression {
			tokens << 'arrow'
		}
		tokens << 'function'
	}
	if is_object_method || is_class_method || is_class_field_method {
		if key >= 0 && t.typ(key) == .private_identifier {
			tokens << '#' + (t.string_of(key, .name) or { '' })
		} else {
			// getPropertyName without a scope.
			mut name := ''
			if key >= 0 {
				if t.flag(parent, .computed) or { false } {
					if ts := t.ts_node(key) {
						name = c.string_if_constant_unscoped(ts) or { '' }
					}
				} else if t.typ(key) == .literal {
					name = es_tree_static_string_value(t, key) or { '' }
				} else {
					name = t.string_of(key, .name) or { '' }
				}
			}
			if name != '' {
				tokens << "'${name}'"
			}
		}
	} else if id := t.node(node, .id) {
		tokens << "'${t.string_of(id, .name) or { '' }}'"
	} else if ptyp == .variable_declarator {
		id := t.node(parent, .id) or { -1 }
		if id >= 0 && t.typ(id) == .identifier {
			tokens << "'${t.string_of(id, .name) or { '' }}'"
		}
	} else if ptyp in [.assignment_expression, .assignment_pattern] {
		left := t.node(parent, .left) or { -1 }
		if left >= 0 && t.typ(left) == .identifier {
			tokens << "'${t.string_of(left, .name) or { '' }}'"
		}
	} else if ptyp == .export_default_declaration
		&& (t.node(parent, .declaration) or { -1 }) == node {
		tokens << "'default'"
	}
	return tokens.join(' ')
}
