module rules

import json2

// Port of the `svelte/sort-attributes` rule of eslint-plugin-svelte 3.24.1: the attributes of a
// start tag in the order of `order` (each entry: a pattern, a list of patterns, or {match, sort}
// whose `alphabetical` sort orders the attributes it matches; a pattern is a name or a `/regexp/`,
// `!` negates it), not across spread attributes. Attributes no entry matches are free. The fix
// moves the attribute before the first one it should precede.

const ssat_messages = {
	'shouldBefore': "Attribute '{{currentKey}}' should go before '{{prevKey}}'."
}

// SsatRule is one pattern of a matcher.
struct SsatRule {
	negative bool
	matcher  SvrxMatcher
}

// SsatOption is a compiled entry of `order`.
struct SsatOption {
	rules        []SsatRule
	alphabetical bool
}

// matches is compileMatcher's matcher.
fn (o &SsatOption) matches(s string) bool {
	if o.rules.len == 0 {
		return false
	}
	mut result := o.rules[0].negative
	for r in o.rules {
		if result == !r.negative {
			continue
		}
		if r.matcher.test(s) {
			result = !r.negative
		}
	}
	return result
}

fn ssat_compile_patterns(patterns []string) ![]SsatRule {
	mut out := []SsatRule{}
	for p in patterns {
		negative := p.starts_with('!')
		out << SsatRule{
			negative: negative
			matcher:  svrx_to_regexp(if negative { p[1..] } else { p })!
		}
	}
	return out
}

fn ssat_string_list(value json2.Any) ![]string {
	if value is string {
		return [value]
	}
	mut out := []string{}
	if value is []json2.Any {
		for v in value {
			if v is string {
				out << v
			}
		}
	}
	return out
}

fn ssat_compile(option json2.Any) !SsatOption {
	if option is map[string]json2.Any {
		sort := option['sort'] or { json2.Any('') }
		return SsatOption{
			rules:        ssat_compile_patterns(ssat_string_list(option['match'] or { json2.Any('') })!)!
			alphabetical: sort is string && sort == 'alphabetical'
		}
	}
	return SsatOption{
		rules: ssat_compile_patterns(ssat_string_list(option)!)!
	}
}

const ssat_default_order = '["this", "bind:this", "id", "name", "slot", {"match": "/^--/u", "sort": "alphabetical"}, ["style", "/^style:/u"], "class", {"match": "/^class:/u", "sort": "alphabetical"}, {"match": ["!/:/u", "!/^(?:this|id|name|style|class)$/u", "!/^--/u"], "sort": "alphabetical"}, ["/^bind:/u", "!bind:this", "/^on:/u"], {"match": "/^use:/u", "sort": "alphabetical"}, {"match": "/^transition:/u", "sort": "alphabetical"}, {"match": "/^in:/u", "sort": "alphabetical"}, {"match": "/^out:/u", "sort": "alphabetical"}, {"match": "/^animate:/u", "sort": "alphabetical"}, {"match": "/^let:/u", "sort": "alphabetical"}]'

fn ssat_options(options []json2.Any) ![]SsatOption {
	o := option_object(svelte_sort_attributes, options, ['order', 'alphabetical'])!
	order := o.values['order'] or { json2.decode[json2.Any](ssat_default_order)! }
	mut out := []SsatOption{}
	if order is []json2.Any {
		for item in order {
			out << ssat_compile(item)!
		}
	}
	return out
}

// ssat_ignore is parseOption's ignore: no entry matches the key.
fn ssat_ignore(order []SsatOption, key string) bool {
	return !order.any(it.matches(key))
}

// ssat_compare is parseOption's compare (keys no entry matches are not compared).
fn ssat_compare(order []SsatOption, a string, b string) int {
	for o in order {
		match_a := o.matches(a)
		match_b := o.matches(b)
		if match_a && match_b {
			if o.alphabetical {
				return if a == b {
					0
				} else if a < b {
					-1
				} else {
					1
				}
			}
			return 0
		}
		if match_a {
			return -1
		}
		if match_b {
			return 1
		}
	}
	return 0
}

fn (mut c Checker) lint_svelte_sort_attributes(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	order := ssat_options(c.rule_options(svelte_sort_attributes))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	mut findings := []Finding{}
	for tag in c.sv_snodes_of(.start_tag) {
		attrs := doc.nodes[tag].attributes
		keys := attrs.map(c.sv_attribute_key_text(it))
		mut valid := []int{} // indexes of attrs
		for k, a in attrs {
			if doc.nodes[a].typ == .spread_attribute {
				continue
			}
			key := keys[k]
			if ssat_ignore(order, key) {
				continue
			}
			mut invalid := -1
			for p in valid {
				if ssat_compare(order, keys[p], key) > 0 {
					invalid = p
					break
				}
			}
			if invalid < 0 {
				valid << k
				continue
			}
			mut has_spread := false
			for p in invalid .. k {
				if doc.nodes[attrs[p]].typ == .spread_attribute {
					has_spread = true
				}
			}
			if !has_spread {
				findings << c.ssat_report(attrs, keys, k, invalid)!
				continue
			}
			// verifyForSpreadAttributeExist: the attributes after the last spread one.
			mut first := k
			for first > 0 && doc.nodes[attrs[first - 1]].typ != .spread_attribute {
				first--
			}
			for p in first .. k {
				if !ssat_ignore(order, keys[p]) && ssat_compare(order, keys[p], key) > 0 {
					findings << c.ssat_report(attrs, keys, k, p)!
					break
				}
			}
		}
	}
	return findings
}

// ssat_report reports attribute k before attribute p, with the fix that moves it there (each
// attribute from p on takes the text of the one before it).
fn (c &Checker) ssat_report(attrs []int, keys []string, k int, p int) !Finding {
	doc := c.svelte.doc
	mut fixes := []Fix{}
	mut moving := [attrs[k]]
	for q in p .. k {
		moving << attrs[q]
	}
	for i, m in moving {
		target := if p + i < k { attrs[p + i] } else { attrs[k] }
		fixes << Fix{
			start: doc.nodes[target].start
			end:   doc.nodes[target].end
			text:  c.sv_snode_text(m)
		}
	}
	has_fix, fix := c.merge_fixes(fixes)!
	return Finding{
		...c.sv_report_snode(attrs[k], 'shouldBefore', {
			'currentKey': keys[k]
			'prevKey':    keys[p]
		})
		has_fix: has_fix
		fix:     fix
	}
}
