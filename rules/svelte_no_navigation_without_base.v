module rules

import estree
import json2

// Port of the `svelte/no-navigation-without-base` rule of eslint-plugin-svelte 3.24.1: the URL of
// `goto`, `pushState` and `replaceState` of `$app/navigation` and the `href` of an `<a>` must
// start with `base` of `$app/paths` (followed through `const` initializers), unless the URL is
// absolute or (for links) a fragment, or empty (shallow routing); options ignore each kind. Its
// condition is a SvelteKit 1 or 2 project.

const svnnwb_messages = {
	'gotoNotPrefixed':         "Found a goto() call with a url that isn't prefixed with the base path."
	'linkNotPrefixed':         "Found a link with a url that isn't prefixed with the base path."
	'pushStateNotPrefixed':    "Found a pushState() call with a url that isn't prefixed with the base path."
	'replaceStateNotPrefixed': "Found a replaceState() call with a url that isn't prefixed with the base path."
}

struct SvnnwbOptions {
	ignore_goto          bool
	ignore_links         bool
	ignore_push_state    bool
	ignore_replace_state bool
}

fn svnnwb_options(options []json2.Any) !SvnnwbOptions {
	o := option_object(svelte_no_navigation_without_base, options, ['ignoreGoto', 'ignoreLinks',
		'ignorePushState', 'ignoreReplaceState'])!
	return SvnnwbOptions{
		ignore_goto:          o.bool_value('ignoreGoto')!
		ignore_links:         o.bool_value('ignoreLinks')!
		ignore_push_state:    o.bool_value('ignorePushState')!
		ignore_replace_state: o.bool_value('ignoreReplaceState')!
	}
}

// svnnwb_is_absolute is expressionIsAbsolute of an ESTree expression of the view.
fn svnnwb_is_absolute(t &estree.EsTree, url int) bool {
	match t.typ(url) {
		.binary_expression {
			left := t.node(url, .left) or { -1 }
			right := t.node(url, .right) or { -1 }
			return (left >= 0 && t.typ(left) != .private_identifier && svnnwb_is_absolute(t, left))
				|| (right >= 0 && svnnwb_is_absolute(t, right))
		}
		.literal {
			value := t.get(url, .value)
			return value is string && svsc_url_is_absolute(value)
		}
		.template_literal {
			return (t.list(url, .expressions) or { []int{} }).any(svnnwb_is_absolute(t, it))
				|| (t.list(url, .quasis) or { []int{} }).any(svsc_url_is_absolute(svsc_raw(t, it)))
		}
		else {
			return false
		}
	}
}

// svnnwb_is_fragment is expressionIsFragment of an ESTree expression of the view.
fn svnnwb_is_fragment(t &estree.EsTree, url int) bool {
	match t.typ(url) {
		.binary_expression {
			left := t.node(url, .left) or { return false }
			return t.typ(left) != .private_identifier && svnnwb_is_fragment(t, left)
		}
		.literal {
			value := t.get(url, .value)
			return value is string && value.starts_with('#')
		}
		.template_literal {
			expressions := t.list(url, .expressions) or { []int{} }
			quasis := t.list(url, .quasis) or { []int{} }
			return (expressions.len >= 1 && svnnwb_is_fragment(t, expressions[0]))
				|| (quasis.len >= 1 && svsc_raw(t, quasis[0]).starts_with('#'))
		}
		else {
			return false
		}
	}
}

// svnnwb_is_empty is expressionIsEmpty.
fn svnnwb_is_empty(t &estree.EsTree, url int) bool {
	if t.typ(url) == .literal {
		value := t.get(url, .value)
		return value is string && value == ''
	}
	if t.typ(url) == .template_literal {
		quasis := t.list(url, .quasis) or { []int{} }
		return (t.list(url, .expressions) or { []int{} }).len == 0 && quasis.len == 1
			&& svsc_raw(t, quasis[0]) == ''
	}
	return false
}

fn (mut c Checker) lint_svelte_no_navigation_without_base(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	o := svnnwb_options(c.rule_options(svelte_no_navigation_without_base))!
	if !c.is_svelte() && !c.src.contains('\$app/navigation') {
		return []
	}
	if !c.svsc_kit_version_in(abs_path, ['1.0.0-next', '1', '2']) {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	b := c.svsc_bridge(root, &e, abs_path) or { return [] }
	t := e.t
	base := c.svsc_base_references(root, &b)
	starts_with_base := fn [mut c, root, e, base] (url int) bool {
		mut visited := map[int]bool{}
		prefix := c.svsc_prefix_variable(root, &e, url, mut visited) or { return false }
		return base[prefix]
	}
	mut findings := []Finding{}
	for traced in c.es_esm_references(root, {
		'\$app/navigation': EsTrace{
			esm:      true
			children: {
				'goto':         EsTrace{
					call: true
				}
				'pushState':    EsTrace{
					call: true
				}
				'replaceState': EsTrace{
					call: true
				}
			}
		}
	}) {
		name := traced.path.last()
		if (name == 'goto' && o.ignore_goto) || (name == 'pushState' && o.ignore_push_state)
			|| (name == 'replaceState' && o.ignore_replace_state) {
			continue
		}
		lint_call := c.es_index_of(b.lint, traced.node) or { continue }
		call := b.view_of(lint_call) or { continue }
		args := t.list(call, .arguments) or { continue }
		if args.len < 1 || args[0] < 0 {
			continue
		}
		url := args[0]
		bad := if name == 'goto' {
			t.typ(url) == .spread_element || !starts_with_base(url)
		} else {
			t.typ(url) == .spread_element || (!svnnwb_is_empty(t, url) && !starts_with_base(url))
		}
		if bad {
			findings << c.svsc_report(&e, url, match name {
				'goto' { 'gotoNotPrefixed' }
				'pushState' { 'pushStateNotPrefixed' }
				else { 'replaceStateNotPrefixed' }
			}, {})
		}
	}
	if !o.ignore_links && e.svelte {
		doc := c.svelte.doc
		for i in c.sv_snodes_of(.attribute) {
			n := doc.nodes[i]
			start_tag := n.parent
			if start_tag < 0 || doc.nodes[start_tag].parent < 0 {
				continue
			}
			element := doc.nodes[doc.nodes[start_tag].parent]
			if element.typ != .element || element.kind != 'html' || element.name_ref.es
				|| element.name_ref.idx < 0 || doc.nodes[element.name_ref.idx].typ != .name
				|| doc.nodes[element.name_ref.idx].name != 'a' || c.sv_attribute_name(i) != 'href'
				|| n.values.len == 0 {
				continue
			}
			value := n.values[0]
			v := doc.nodes[value]
			if v.typ == .literal {
				if !svsc_url_is_absolute(v.value) && !v.value.starts_with('#') {
					findings << c.sv_report_snode(value, 'linkNotPrefixed', {})
				}
				continue
			}
			if !v.expression.es || v.expression.idx < 0 {
				continue
			}
			expression := v.expression.idx
			if !starts_with_base(expression) && !svnnwb_is_absolute(t, expression)
				&& !svnnwb_is_fragment(t, expression) {
				findings << c.sv_report_snode(value, 'linkNotPrefixed', {})
			}
		}
	}
	return findings
}
