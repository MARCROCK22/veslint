module rules

import estree
import vue

// Parts of eslint-plugin-vue 10.12.1's lib/utils (index.ts) for the ESTree nodes of template
// expressions (a node of the EsTree of a snippet: Document.snippets[s].es) and for the template's
// elements, beyond those of vue_template.v.

// vue_equal_tokens is equalTokens with the template's token store: the tokens of the two ranges
// have the same types and values.
fn (c &Checker) vue_equal_tokens(a_start int, a_end int, b_start int, b_end int) bool {
	left := c.vue_tokens_in(a_start, a_end)
	right := c.vue_tokens_in(b_start, b_end)
	if left.len != right.len {
		return false
	}
	for i, token in left {
		if token.typ != right[i].typ || token.value != right[i].value {
			return false
		}
	}
	return true
}

// vue_child_element_chains is iterateChildElementsChains: the child elements of `element` in
// groups, each a v-if / v-else-if / v-else chain or an element alone.
fn (c &Checker) vue_child_element_chains(element int) [][]int {
	mut out := [][]int{}
	mut is_v_if := false
	mut chain := []int{}
	for child in c.vue.doc.nodes[element].children {
		node := &c.vue.doc.nodes[child]
		if node.typ == .v_element {
			mut connected := false
			if c.vue_has_directive(child, 'if', none) {
				is_v_if = true
			} else if c.vue_has_directive(child, 'else-if', none) {
				connected = is_v_if
				is_v_if = true
			} else if c.vue_has_directive(child, 'else', none) {
				connected = is_v_if
				is_v_if = false
			} else {
				is_v_if = false
			}
			if connected {
				chain << child
			} else {
				if chain.len > 0 {
					out << chain
				}
				chain = [child]
			}
		} else if node.typ != .v_text || js_trim(node.text) != '' {
			is_v_if = false
		}
	}
	if chain.len > 0 {
		out << chain
	}
	return out
}

// vue_split_whitespace is `text.split(/\s+/)`: the pieces between runs of JavaScript white space
// (an empty piece before a leading run and after a trailing one).
fn vue_split_whitespace(text string) []string {
	mut out := []string{}
	mut piece := []rune{}
	mut in_space := false
	for r in text.runes() {
		if is_js_space(r) {
			if !in_space {
				out << piece.string()
				piece = []rune{}
				in_space = true
			}
			continue
		}
		in_space = false
		piece << r
	}
	out << piece.string()
	return out
}

// vue_variable_name is `variable.id.name`.
fn (c &Checker) vue_variable_name(v int) string {
	return c.vue.doc.variables[v].name
}

// vue_expr_es is the EsTree of an Expr of a snippet.
fn (c &Checker) vue_expr_es(e vue.Expr) &estree.EsTree {
	return &c.vue.doc.snippets[e.snippet].es
}
