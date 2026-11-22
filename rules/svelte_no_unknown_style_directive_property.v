module rules

import json2

// Port of the `svelte/no-unknown-style-directive-property` rule of eslint-plugin-svelte 3.24.1:
// the property of a `style:` directive must be a custom property (`--x`), one of
// known-css-properties 0.37.0, one of ignoreProperties (names or `/regexp/` strings) or, with
// ignorePrefixed (the default), one with a vendor prefix.

const snusdp_messages = {
	'unknown': "Unexpected unknown style directive property '{{property}}'."
}

struct SnusdpOptions {
	ignore_properties []SvrxMatcher
	ignore_prefixed   bool = true
}

fn snusdp_options(options []json2.Any) !SnusdpOptions {
	o := option_object(svelte_no_unknown_style_directive_property, options, [
		'ignoreProperties',
		'ignorePrefixed',
	])!
	mut ignore := []SvrxMatcher{}
	for p in o.string_list('ignoreProperties')! {
		ignore << svrx_to_regexp(p)!
	}
	return SnusdpOptions{
		ignore_properties: ignore
		ignore_prefixed:   if 'ignorePrefixed' in o.values {
			o.bool_value('ignorePrefixed')!
		} else {
			true
		}
	}
}

fn (mut c Checker) lint_svelte_no_unknown_style_directive_property(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := snusdp_options(c.rule_options(svelte_no_unknown_style_directive_property))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for i in c.sv_snodes_of(.style_directive) {
		key := doc.nodes[doc.nodes[i].key.idx]
		name := c.sv_ref_name(key.key)
		if name.starts_with('--') || name in svst_known_css_properties
			|| options.ignore_properties.any(it.test(name))
			|| (options.ignore_prefixed && svst_vendor_prefix(name) != '') {
			continue
		}
		findings << c.sv_report_ref(key.key, 'unknown', {
			'property': name
		})
	}
	return findings
}
