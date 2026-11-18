module rules

import estree
import treesitter { node_kind }

// Port of the `svelte/no-goto-without-base` rule of eslint-plugin-svelte 3.24.1 (deprecated for
// no-navigation-without-resolve): the URL given to `goto` of `$app/navigation` must start with
// `base` of `$app/paths` (`base + …`, `` `${base}…` ``) unless it is a literal with a scheme. Its
// condition is a SvelteKit 1 or 2 project: it lints any file there.

const svngwb_messages = {
	'isNotPrefixedWithBasePath': "Found a goto() call with a url that isn't prefixed with the base path."
}

// svngwb_base_references are extractBasePathReferences: the identifiers of the references to
// `base` imported from `$app/paths` (node keys of the lint code's tree).
fn (mut c Checker) svngwb_base_references(root C.TSNode) map[u64]bool {
	mut out := map[u64]bool{}
	tree := c.scope_tree(root)
	for traced in c.es_esm_references(root, {
		'\$app/paths': EsTrace{
			esm:      true
			children: {
				'base': EsTrace{
					read: true
				}
			}
		}
	}) {
		v := c.svsc_import_variable(root, traced.node)
		if v < 0 {
			continue
		}
		for r in tree.variables[v].references {
			identifier := tree.references[r].identifier
			if node_kind(identifier) == 'identifier' {
				out[node_key(identifier)] = true
			}
		}
	}
	return out
}

// svngwb_is_base: the ESTree node is an Identifier among the references to `base`.
fn svngwb_is_base(t &estree.EsTree, node int, base map[u64]bool) bool {
	if node < 0 || t.typ(node) != .identifier {
		return false
	}
	ts := t.ts_node(node) or { return false }
	return node_key(ts) in base
}

// svngwb_starts_with_base is extractStartingIdentifier of a template literal checked against the
// references to `base`.
fn svngwb_starts_with_base(t &estree.EsTree, template int, base map[u64]bool) bool {
	mut parts := t.list(template, .expressions) or { []int{} }
	parts << t.list(template, .quasis) or { []int{} }
	parts.sort_with_compare(fn [t] (a &int, b &int) int {
		return if t.nodes[*a].start < t.nodes[*b].start { -1 } else { 1 }
	})
	for part in parts {
		if t.typ(part) == .template_element {
			value := t.get(part, .value)
			if value is estree.TemplateValue && value.raw == '' {
				continue
			}
		}
		return svngwb_is_base(t, part, base)
	}
	return false
}

// svngwb_has_scheme is `/^[+a-z]*:/i.test(path.value?.toString() ?? '')` for a Literal.
fn svngwb_has_scheme(t &estree.EsTree, literal int) bool {
	value := t.get(literal, .value)
	text := if value is string { value } else { return false }
	for ch in text {
		if ch == `:` {
			return true
		}
		if !(ch == `+` || (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)) {
			return false
		}
	}
	return false
}

fn (mut c Checker) lint_svelte_no_goto_without_base(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.src.contains('\$app/navigation')
		|| !c.svsc_kit_version_in(abs_path, ['1.0.0-next', '1', '2']) {
		return []
	}
	t := c.es_tree(root, abs_path) or { return [] }
	base := c.svngwb_base_references(root)
	mut findings := []Finding{}
	for traced in c.es_esm_references(root, {
		'\$app/navigation': EsTrace{
			esm:      true
			children: {
				'goto': EsTrace{
					call: true
				}
			}
		}
	}) {
		call := c.es_index_of(t, traced.node) or { continue }
		args := t.list(call, .arguments) or { continue }
		if args.len < 1 || args[0] < 0 {
			continue
		}
		path := args[0]
		ok := match t.typ(path) {
			.binary_expression { svngwb_is_base(t, t.node(path, .left) or { -1 }, base) }
			.literal { svngwb_has_scheme(t, path) }
			.template_literal { svngwb_starts_with_base(t, path, base) }
			else { false }
		}
		if !ok {
			findings << Finding{
				stmt:       c.es_tree_position(t, path)
				message_id: 'isNotPrefixedWithBasePath'
			}
		}
	}
	return c.svsc_moved(findings)
}
