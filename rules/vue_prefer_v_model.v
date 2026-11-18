module rules

import estree
import time
import vue

// Port of the `vue/prefer-v-model` rule of eslint-plugin-vue 10.12.1: on a custom component, a
// `:prop="x"` (static argument, no modifiers) with a `@update:prop` (the same name in camel case)
// whose handler only assigns the event to `x` (`x = $event` or `(v) => x = v`), with a suggestion
// that writes `v-model:prop="x"` (`v-model` for modelValue) and removes the `@update:` with the
// white space before it.

const vpvm_messages = {
	'preferVModel':      'Prefer `{{ vModelName }}` over the `:{{ propName }}`/`@update:{{ eventName }}` pair.'
	'replaceWithVModel': 'Replace with `{{ vModelName }}`.'
}

// vpvm_static_arg_name is getStaticArgName: the rawName of a VIdentifier argument.
fn (c &Checker) vpvm_static_arg_name(attr int) ?string {
	key := &c.vue.doc.nodes[c.vue.doc.nodes[attr].key]
	if key.argument < 0 || c.vue.doc.nodes[key.argument].typ != .v_identifier {
		return none
	}
	return c.vue.doc.nodes[key.argument].raw_name
}

fn (c &Checker) vpvm_update_prop_name(attr int) ?string {
	name := c.vpvm_static_arg_name(attr)?
	if name.starts_with('update:') {
		return name['update:'.len..]
	}
	return none
}

fn (c &Checker) vpvm_expr_text(e vue.Expr) string {
	start, end := c.vue_expr_range(e)
	return c.vue_text(start, end)
}

// vpvm_is_mirror_assignment is isMirrorAssignment.
fn (c &Checker) vpvm_is_mirror_assignment(bind_expr vue.Expr, on_expr vue.Expr) bool {
	bind_text := c.vpvm_expr_text(bind_expr)
	if on_expr.kind == .vnode {
		on := &c.vue.doc.nodes[on_expr.node]
		if on.typ != .v_on_expression || on.exprs.len != 1 || on.exprs[0].kind != .estree {
			return false
		}
		stmt := on.exprs[0]
		t := c.vue_expr_es(stmt)
		if t.typ(stmt.node) != .expression_statement {
			return false
		}
		expr := t.node(stmt.node, .expression) or { return false }
		return c.vpvm_assigns(t, expr, bind_text, '$event')
	}
	if on_expr.kind == .estree {
		t := c.vue_expr_es(on_expr)
		if t.typ(on_expr.node) != .arrow_function_expression {
			return false
		}
		params := t.list(on_expr.node, .params) or { return false }
		if params.len != 1 || t.typ(params[0]) != .identifier {
			return false
		}
		param_name := t.string_of(params[0], .name) or { return false }
		body := t.node(on_expr.node, .body) or { return false }
		return c.vpvm_assigns(t, body, bind_text, param_name)
	}
	return false
}

// vpvm_assigns: `expr` is `<bind_text> = <name>`.
fn (c &Checker) vpvm_assigns(t &estree.EsTree, expr int, bind_text string, name string) bool {
	if t.typ(expr) != .assignment_expression || (t.string_of(expr, .operator) or { '' }) != '=' {
		return false
	}
	left := t.node(expr, .left) or { return false }
	right := t.node(expr, .right) or { return false }
	return c.vue_text(t.nodes[left].start, t.nodes[left].end) == bind_text
		&& t.typ(right) == .identifier && (t.string_of(right, .name) or { '' }) == name
}

fn (mut c Checker) lint_vue_prefer_v_model(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		node := &c.vue.doc.nodes[i]
		if node.typ != .v_start_tag || !c.vue_is_custom_component(node.parent, false) {
			continue
		}
		stats.checked++
		mut binds := []int{}
		mut ons := []int{}
		for a in node.attributes {
			attr := &c.vue.doc.nodes[a]
			if !attr.directive {
				continue
			}
			no_modifiers := c.vue.doc.nodes[attr.key].modifiers.len == 0
			name := c.vue_directive_name(a)
			if name == 'bind' && no_modifiers && (c.vpvm_static_arg_name(a) or { '\x00' }) != '\x00' {
				binds << a
			}
			if name == 'on' && no_modifiers && (c.vpvm_update_prop_name(a) or { '\x00' }) != '\x00' {
				ons << a
			}
		}
		for bind in binds {
			prop_name := c.vpvm_static_arg_name(bind) or { continue }
			if prop_name == '' {
				continue
			}
			normalized := vue_camel_case(prop_name)
			mut on := -1
			for o in ons {
				if vue_camel_case(c.vpvm_update_prop_name(o) or { '' }) == normalized {
					on = o
					break
				}
			}
			if on < 0 {
				continue
			}
			bind_node := &c.vue.doc.nodes[bind]
			on_node := &c.vue.doc.nodes[on]
			bind_expr := c.vue_container_expression(bind_node.value)
			on_expr := c.vue_container_expression(on_node.value)
			if on_expr.is_null() || bind_expr.is_null() {
				continue
			}
			if c.vue_expr_type(bind_expr) in ['VFilterSequenceExpression', 'VForExpression',
				'VOnExpression', 'VSlotScopeExpression'] {
				continue
			}
			if !c.vpvm_is_mirror_assignment(bind_expr, on_expr) {
				continue
			}
			v_model_name := if normalized == 'modelValue' {
				'v-model'
			} else {
				'v-model:${prop_name}'
			}
			event_name := c.vpvm_update_prop_name(on) or { prop_name }
			v_model_text := '${v_model_name}=${c.vue_vnode_text(bind_node.value)}'
			remove_start := vu4_trim_end_offset(c.vue.doc.src, on_node.start)
			ok, suggestion := c.suggestion('replaceWithVModel', {
				'vModelName': v_model_name
			}, [fix_replace_range(bind_node.start, bind_node.end, v_model_text),
				fix_remove_range(remove_start, on_node.end)])!
			finding := c.vue_report_vnode(bind, 'preferVModel', {
				'vModelName': v_model_name
				'propName':   prop_name
				'eventName':  event_name
			})
			findings << Finding{
				...finding
				suggestions: if ok { [suggestion] } else { []Suggestion{} }
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
