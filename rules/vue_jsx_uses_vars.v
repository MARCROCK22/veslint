module rules

import treesitter { named_children, node_end, node_field, node_kind, node_start }

// Port of the `vue/jsx-uses-vars` rule of eslint-plugin-vue 10.12.1 (no options): it reports
// nothing; its JSXOpeningElement listener marks the variable named by the element (the
// leftmost object of a member name) as used (sourceCode.markVariableAsUsed), which other rules
// read (no-unused-vars). veslint marks it when it builds the scopes of a file this rule runs on
// (scope_tree).

const vue_jsx_uses_vars_messages = map[string]string{}

fn (mut c Checker) lint_vue_jsx_uses_vars(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	return []
}

// vue_mark_jsx_uses_vars ports the rule's markVariableAsUsed: from the scope of each JSX opening
// element (the module scope for the top level), the first variable of the name upward gets
// eslintUsed.
fn vue_mark_jsx_uses_vars(root C.vt_node, src string, mut tree ScopeTree) {
	mut stack := [root]
	for stack.len > 0 {
		n := stack.pop()
		kind := node_kind(n)
		if kind in ['jsx_opening_element', 'jsx_self_closing_element'] {
			if name := vue_jsx_element_variable_name(n, src) {
				v := tree.find_variable(tree.get_scope(n), name, -1)
				if v >= 0 {
					tree.variables[v].eslint_used = true
				}
			}
		}
		kids := named_children(n)
		for i := kids.len - 1; i >= 0; i-- {
			stack << kids[i]
		}
	}
}

// vue_jsx_element_variable_name is the name the rule marks: a JSXIdentifier's, or the leftmost
// object of a JSXMemberExpression; none for a namespaced name.
fn vue_jsx_element_variable_name(element C.vt_node, src string) ?string {
	mut name := node_field(element, 'name') or { return none }
	for node_kind(name) in ['member_expression', 'nested_identifier'] {
		name = node_field(name, 'object') or { return none }
	}
	if node_kind(name) !in ['identifier', 'jsx_identifier', 'this'] {
		return none
	}
	return src[node_start(name)..node_end(name)]
}
