module rules

import json2
import postcss

// Port of the `svelte/no-unused-class-name` rule of eslint-plugin-svelte 3.24.1: a class of an
// HTML element (a word of its `class` attribute's text, or a class directive) that no selector
// of the <style> element uses and that allowedClassNames (names or `/regexp/` strings) does not
// allow, reported at the element's start tag. Nothing is reported when the <style> element
// cannot be parsed or its lang is unknown.

const snucn_messages = map[string]string{}

fn snucn_options(options []json2.Any) ![]SvrxMatcher {
	o := option_object(svelte_no_unused_class_name, options, ['allowedClassNames'])!
	mut out := []SvrxMatcher{}
	for name in o.string_list('allowedClassNames')! {
		out << svrx_to_regexp(name)!
	}
	return out
}

fn (mut c Checker) lint_svelte_no_unused_class_name(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	allowed := snucn_options(c.rule_options(svelte_no_unused_class_name))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut used := [][]int{} // [element, attribute] with its classes in `names`
	mut names := []string{}
	for el in c.sv_snodes_of(.element) {
		n := doc.nodes[el]
		if n.kind != 'html' || n.start_tag < 0 {
			continue
		}
		for a in doc.nodes[n.start_tag].attributes {
			for class_name in c.svaf_classes_in_attribute(a) {
				used << [n.start_tag]
				names << class_name
			}
		}
	}
	ctx := c.svst_style_context(abs_path)
	if ctx.status in [.parse_error, .unknown_lang] {
		return []
	}
	mut in_style := map[string]bool{}
	if ctx.status == .success {
		snucn_classes_of_node(&ctx.root, 0, mut in_style)
	}
	mut findings := []Finding{}
	for k, class_name in names {
		if allowed.any(it.test(class_name)) || class_name in in_style {
			continue
		}
		tag := used[k][0]
		findings << c.sv_report_message(doc.nodes[tag].start, c.sv_snode_loc_end(tag), 'Unused class "${class_name}".')
	}
	return findings
}

// snucn_classes_of_node is findClassesInPostCSSNode: the classes of the selectors of the rules
// (also inside :global(...)), through the at-rules.
fn snucn_classes_of_node(root &postcss.Root, i int, mut out map[string]bool) {
	n := root.nodes[i]
	if n.typ == .rule {
		for k in n.nodes {
			snucn_classes_of_node(root, k, mut out)
		}
		// A selector postcss-selector-parser cannot parse makes the rule crash in ESLint.
		if sel := postcss.parse_selector(n.selector) {
			snucn_classes_of_selector(&sel, 0, mut out)
		}
		return
	}
	if (n.typ == .root || n.typ == .atrule) && n.has_nodes {
		for k in n.nodes {
			snucn_classes_of_node(root, k, mut out)
		}
	}
}

fn snucn_classes_of_selector(sel &postcss.SelectorRoot, i int, mut out map[string]bool) {
	n := sel.nodes[i]
	if n.typ == .class {
		out[n.value] = true
		return
	}
	if n.typ in [.pseudo, .root, .selector] {
		for k in n.nodes {
			snucn_classes_of_selector(sel, k, mut out)
		}
	}
}
