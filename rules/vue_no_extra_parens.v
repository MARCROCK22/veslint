module rules

import vue

// The listeners vue/no-extra-parens (eslint-plugin-vue 10.12.1) adds to the rule it wraps
// (createForVueSyntax): the parentheses around the whole expression of a v-bind or of a mustache
// (or of a v-bind() of a <style>), which the wrapped rule does not see. On the document's tokens
// (the template token store), in file offsets.

// vnep_paren is isOpeningParenToken / isClosingParenToken.
fn vnep_paren(t vue.Token, value string) bool {
	return t.typ == 'Punctuator' && t.value == value
}

// vnep_parenthesized ports eslint-utils' isParenthesized(times, node) on the token store, for a
// node whose parent is no call (a container): `times` pairs of parentheses around [start, end).
fn (c &Checker) vnep_parenthesized(times int, start int, end int) bool {
	mut left_at := start
	mut right_at := end
	mut n := times
	for {
		left := c.vue_token_before(left_at, false) or { return false }
		right := c.vue_token_after(right_at, false) or { return false }
		if !vnep_paren(left, '(') || !vnep_paren(right, ')') {
			return false
		}
		n--
		if n == 0 {
			return true
		}
		left_at = left.start
		right_at = right.end
	}
	return false
}

// vnep_unwrap_changes_to_filter ports isUnwrapChangeToFilter: a `|` outside the brackets of the
// expression.
fn (c &Checker) vnep_unwrap_changes_to_filter(start int, end int) bool {
	mut stack := []string{}
	for token in c.vue_tokens_in(start, end) {
		if stack.len > 0 {
			if vnep_paren(token, stack.last()) {
				stack.pop()
				continue
			}
		} else if token.value == '|' {
			return true
		}
		if vnep_paren(token, '(') {
			stack << ')'
		} else if vnep_paren(token, '[') {
			stack << ']'
		} else if vnep_paren(token, '{') {
			stack << '}'
		}
	}
	return false
}

// vnep_style_variable_without_quote ports isStyleVariableWithoutQuote: the container is a
// v-bind() of a top-level <style> and only `(` are between its first token and the expression.
fn (c &Checker) vnep_style_variable_without_quote(container int, start int) bool {
	doc := c.vue.doc
	node := &doc.nodes[container]
	if node.parent < 0 {
		return false
	}
	style := &doc.nodes[node.parent]
	if style.typ != .v_element || style.name != 'style' || style.parent != 0 {
		return false
	}
	first := c.vue_first_token_in(node.start, node.end) or { return false }
	for token in c.vue_tokens_in(first.end, start) {
		if !vnep_paren(token, '(') {
			return false
		}
	}
	return true
}

// vnep_vue_syntax runs createForVueSyntax's listeners on the document.
fn (mut c Checker) vnep_vue_syntax() ![]Finding {
	mut findings := []Finding{}
	doc := c.vue.doc
	for step in c.vue_document_steps() {
		if step.leave || step.node.kind != .vnode {
			continue
		}
		i := step.node.v
		node := &doc.nodes[i]
		if node.typ != .v_expression_container || node.parent < 0 {
			continue
		}
		parent := &doc.nodes[node.parent]
		on_bind := parent.typ == .v_attribute && parent.directive && parent.value == i
			&& c.vue_directive_name(node.parent) == 'bind'
		if !on_bind && parent.typ != .v_element {
			continue
		}
		mut expression := node.expression
		if expression.kind == .vnode && doc.nodes[expression.node].typ == .v_filter_sequence_expression {
			expression = doc.nodes[expression.node].expression
		}
		if expression.kind != .estree {
			continue
		}
		es := &doc.snippets[expression.snippet].es
		e := expression.node
		start := es.nodes[e].start
		end := es.nodes[e].end
		if !c.vnep_parenthesized(1, start, end) {
			continue
		}
		mut iife_callee_bare := false
		if es.typ(e) == .call_expression {
			if callee := es.node(e, .callee) {
				if es.typ(callee) == .function_expression {
					iife_callee_bare = !c.vnep_parenthesized(1, es.nodes[callee].start,
						es.nodes[callee].end)
				}
			}
		}
		if !c.vnep_parenthesized(2, start, end) && (iife_callee_bare
			|| c.vnep_unwrap_changes_to_filter(start, end)
			|| c.vnep_style_variable_without_quote(i, start)) {
			continue
		}
		left := c.vue_token_before(start, false) or { continue }
		right := c.vue_token_after(end, false) or { continue }
		findings << c.with_fixes(c.vue_report(left.start, left.end, 'unexpected', {}), [
			Fix{
				start: left.start
				end:   right.end
				text:  doc.src[left.end..right.start]
			},
		])!
	}
	return findings
}
