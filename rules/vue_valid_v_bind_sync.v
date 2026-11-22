module rules

import estree
import time

// Port of the `vue/valid-v-bind-sync` rule of eslint-plugin-vue 10.12.1 (deprecated): a `v-bind`
// with the `.sync` modifier on an element that is not a custom component, or whose value is an
// optional chain, not valid as the left-hand side of an assignment, a member access of a possibly
// null object, or an iteration variable itself.

const vvbsync_messages = {
	'unexpectedInvalidElement':          "'.sync' modifiers aren't supported on <{{name}}> non Vue-components."
	'unexpectedOptionalChaining':        "Optional chaining cannot appear in 'v-bind' with '.sync' modifiers."
	'unexpectedNonLhsExpression':        "'.sync' modifiers require the attribute value which is valid as LHS."
	'unexpectedNullObject':              "'.sync' modifier has potential null object property access."
	'unexpectedUpdateIterationVariable': "'.sync' modifiers cannot update the iteration variable '{{varName}}' itself."
}

// vvbsync_maybe_null_object is isMaybeNullObjectMemberExpression.
fn vvbsync_maybe_null_object(es &estree.EsTree, node int) bool {
	if es.typ(node) != .member_expression {
		return false
	}
	object := es.node(node, .object) or { return false }
	return match es.typ(object) {
		.chain_expression {
			true
		}
		.literal {
			es.get(object, .value) is estree.Null && es.prop(object, .bigint) == none
		}
		.member_expression {
			vvbsync_maybe_null_object(es, object)
		}
		else {
			false
		}
	}
}

fn (mut c Checker) lint_vue_valid_v_bind_sync(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	for i in c.vue_template_vnodes() {
		if !c.vue_is_directive(i, 'bind') {
			continue
		}
		if !c.vue_directive_modifiers(i).any(c.vue.doc.nodes[it].name == 'sync') {
			continue
		}
		stats.checked++
		node := &c.vue.doc.nodes[i]
		element := c.vue_attribute_element(i)
		if !c.vue_is_custom_component(element, false) {
			findings << c.vue_report_vnode(i, 'unexpectedInvalidElement', {
				'name': c.vue.doc.nodes[element].name
			})
		}
		if node.value < 0 {
			continue
		}
		e := c.vue_container_expression(node.value)
		if e.is_null() {
			continue
		}
		start, end := c.vue_expr_range(e)
		typ := c.vue_expr_type(e)
		if e.kind == .estree && typ == 'ChainExpression'
			&& c.vue_expr_es(e).typ(c.vue_expr_es(e).node(e.node, .expression) or { -1 }) == .member_expression {
			findings << c.vue_report(start, end, 'unexpectedOptionalChaining', {})
		} else if typ != 'Identifier' && typ != 'MemberExpression' {
			findings << c.vue_report(start, end, 'unexpectedNonLhsExpression', {})
		} else if vvbsync_maybe_null_object(c.vue_expr_es(e), e.node) {
			findings << c.vue_report(start, end, 'unexpectedNullObject', {})
		}
		for r in c.vue.doc.nodes[node.value].references {
			reference := &c.vue.doc.references[r]
			// `id.parent.type === 'VExpressionContainer'`: the identifier is the whole expression.
			if reference.id.snippet != e.snippet || reference.id.node != e.node
				|| reference.id.kind != .estree || reference.variable < 0 {
				continue
			}
			findings << c.vue_report(start, end, 'unexpectedUpdateIterationVariable', {
				'varName': reference.name
			})
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
