module rules

import json2

// Port of the `svelte/no-target-blank` rule of eslint-plugin-svelte 3.24.1: a `target="_blank"`
// attribute of an element with an external link (an `href` starting with a scheme or `//`) or,
// with enforceDynamicLinks "always" (the default), a dynamic one, needs `rel="noopener
// noreferrer"` (`noopener` alone with allowReferrer). The rule reports with a message of its own.

const sntb_messages = {
	'disallow': 'Using target="_blank" without rel="noopener noreferrer" is a security risk.'
}

struct SntbOptions {
	allow_referrer bool
	enforce_always bool = true
}

fn sntb_options(options []json2.Any) !SntbOptions {
	o := option_object(svelte_no_target_blank, options, ['allowReferrer', 'enforceDynamicLinks'])!
	enforce := o.string_value('enforceDynamicLinks', ['always', 'never'])!
	return SntbOptions{
		allow_referrer: o.bool_value('allowReferrer')!
		enforce_always: enforce != 'never'
	}
}

// sntb_has_secure_rel is hasSecureRel: the start tag's rel has noopener (and noreferrer unless
// allowReferrer), among the words of its static parts.
fn (c &Checker) sntb_has_secure_rel(tag int, allow_referrer bool) bool {
	attr := c.sv_find_attribute(tag, 'rel')
	if attr < 0 {
		return false
	}
	doc := c.svelte.doc
	mut tags := []string{}
	for v in doc.nodes[attr].values {
		if doc.nodes[v].typ == .literal {
			tags << vue_js_to_lower(doc.nodes[v].value).split(' ')
		}
	}
	return 'noopener' in tags && (allow_referrer || 'noreferrer' in tags)
}

// sntb_is_external is /^(?:\w+:|\/\/)/ on a text.
fn sntb_is_external(text string) bool {
	if text.starts_with('//') {
		return true
	}
	mut i := 0
	for i < text.len && (text[i].is_letter() || text[i].is_digit() || text[i] == `_`) {
		i++
	}
	return i > 0 && i < text.len && text[i] == `:`
}

// sntb_has_external_link is hasExternalLink.
fn (c &Checker) sntb_has_external_link(tag int) bool {
	doc := c.svelte.doc
	for a in doc.nodes[tag].attributes {
		n := doc.nodes[a]
		if n.typ == .attribute && c.sv_attribute_name(a) == 'href' && n.values.len >= 1
			&& doc.nodes[n.values[0]].typ == .literal
			&& sntb_is_external(doc.nodes[n.values[0]].value) {
			return true
		}
	}
	return false
}

// sntb_has_dynamic_link is hasDynamicLink.
fn (c &Checker) sntb_has_dynamic_link(tag int) bool {
	doc := c.svelte.doc
	attr := c.sv_find_attribute(tag, 'href')
	if attr >= 0 {
		return doc.nodes[attr].values.any(doc.nodes[it].typ == .mustache_tag)
	}
	return c.sv_find_shorthand_attribute(tag, 'href') >= 0
		|| c.sv_find_bind_directive(tag, 'href') >= 0
}

fn (mut c Checker) lint_svelte_no_target_blank(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	options := sntb_options(c.rule_options(svelte_no_target_blank))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for attr in c.sv_snodes_of(.attribute) {
		if c.sv_attribute_name(attr) != 'target' {
			continue
		}
		value := c.sv_static_attribute_value(attr) or { continue }
		tag := doc.nodes[attr].parent
		if value != '_blank' || c.sntb_has_secure_rel(tag, options.allow_referrer) {
			continue
		}
		if c.sntb_has_external_link(tag)
			|| (options.enforce_always && c.sntb_has_dynamic_link(tag)) {
			n := doc.nodes[attr]
			findings << c.sv_report_message(n.start, if n.loc_end >= 0 { n.loc_end } else { n.end },
				sntb_messages['disallow'])
		}
	}
	return findings
}
