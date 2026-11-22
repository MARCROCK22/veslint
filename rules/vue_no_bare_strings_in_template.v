module rules

import jsregexp
import json2
import time

// Port of the `vue/no-bare-strings-in-template` rule of eslint-plugin-vue 10.12.1 (options
// `allowlist`, strings or `/regexps/`; `attributes`, the attributes to check by element name or
// `/regexp/`; `directives`): a text of the template, a checked attribute's value or a checked
// directive's string literal that is more than white space and allowed strings.

const vnbs_messages = {
	'unexpected':       'Unexpected non-translated string used.'
	'unexpectedInAttr': 'Unexpected non-translated string used in `{{attr}}`.'
}

const vnbs_default_allowlist = ['(', ')', ',', '.', '&', '+', '-', '=', '*', '/', '#', '%', '!',
	'?', ':', '[', ']', '{', '}', '<', '>', '·', '•', '‐', '–', '—', '−', '|']

struct VnbsRegex {
	re      jsregexp.JsRegex
	unicode bool
}

struct VnbsAttrRegex {
	name  jsregexp.JsRegex
	attrs []string
}

struct VnbsOptions {
	strings      []string // the allowlist's strings, longest first
	regexps      []VnbsRegex
	attr_names   map[string][]string
	attr_regexps []VnbsAttrRegex
	directives   []string
}

fn vnbs_options(options []json2.Any) !VnbsOptions {
	o := option_object(vue_no_bare_strings_in_template, options, ['allowlist', 'attributes',
		'directives'])!
	raw := if 'allowlist' in o.values {
		o.string_list('allowlist')!
	} else {
		vnbs_default_allowlist
	}
	mut strings := []string{}
	mut regexps := []VnbsRegex{}
	for item in raw {
		if source, flags := vue_regexp_str(item) {
			kept := flags.replace('g', '').replace('y', '')
			regexps << VnbsRegex{
				re:      jsregexp.js_regex_new(source, kept)!
				unicode: flags.contains('u')
			}
		} else {
			strings << item
		}
	}
	// `.sort((a, b) => b.length - a.length)` on the escaped strings: a stable sort by length.
	// (by UTF-16 length; an insertion sort keeps the order of equal lengths).
	mut keyed := []VnbsKeyed{}
	for w in strings {
		item := VnbsKeyed{utf16_units(vue_regexp_escape(w)).len, w}
		mut at := keyed.len
		for at > 0 && keyed[at - 1].len < item.len {
			at--
		}
		keyed.insert(at, item)
	}
	mut attr_names := map[string][]string{}
	mut attr_regexps := []VnbsAttrRegex{}
	mut attributes := map[string]json2.Any{}
	if value := o.values['attributes'] {
		if value !is map[string]json2.Any {
			return error('option `attributes` of `${vue_no_bare_strings_in_template}` must be an object')
		}
		attributes = value.as_map()
	} else {
		attributes = {
			'/.+/':  json2.Any(['title', 'aria-label', 'aria-placeholder', 'aria-roledescription',
				'aria-valuetext'].map(json2.Any(it)))
			'input': json2.Any([json2.Any('placeholder')])
			'img':   json2.Any([json2.Any('alt')])
		}
	}
	for name, list in attributes {
		if list !is []json2.Any {
			return error('`attributes` of `${vue_no_bare_strings_in_template}` must hold lists')
		}
		mut attrs := []string{}
		for a in list.as_array() {
			if a !is string {
				return error('`attributes` of `${vue_no_bare_strings_in_template}` must hold texts')
			}
			if a as string !in attrs {
				attrs << a as string
			}
		}
		if vue_is_regexp(name) {
			attr_regexps << VnbsAttrRegex{
				name:  vue_to_regexp(name, '', 'gy')!
				attrs: attrs
			}
		} else {
			attr_names[name] = attrs
		}
	}
	return VnbsOptions{
		strings:      keyed.map(it.text)
		regexps:      regexps
		attr_names:   attr_names
		attr_regexps: attr_regexps
		directives:   if 'directives' in o.values {
			o.string_list('directives')!
		} else {
			['v-text']
		}
	}
}

struct VnbsKeyed {
	len  int
	text string
}

// vnbs_remove_strings is `str.replace(allowlistRe, '')`: at each place, the first string of the
// list that is there is removed.
fn vnbs_remove_strings(s string, list []string) string {
	if list.len == 0 {
		return s
	}
	mut out := []u8{cap: s.len}
	mut k := 0
	for k < s.len {
		mut matched := -1
		for w in list {
			if s[k..].starts_with(w) {
				matched = w.len
				break
			}
		}
		if matched > 0 {
			k += matched
			continue
		}
		// An empty alternative matches: the character stays.
		len := utf8_char_len(s[k])
		end := if k + len <= s.len { k + len } else { s.len }
		out << s[k..end].bytes()
		k = end
	}
	return out.bytestr()
}

// vu4_regex_remove_all is `s.replace(new RegExp(source, flags + 'g'), '')`.
fn vu4_regex_remove_all(re &jsregexp.JsRegex, unicode bool, s string) string {
	units := utf16_units(s)
	seq := if unicode { jsregexp.utf16_code_points(units) } else { units.map(u32(it)) }
	mut out := []u32{cap: seq.len}
	mut last := 0
	mut from := 0
	for from <= seq.len {
		found, start, end, _ := re.exec(units, from) or { break }
		if !found {
			break
		}
		out << seq[last..start]
		last = end
		from = if end == start { end + 1 } else { end }
	}
	out << seq[last..]
	if unicode {
		return out.map(rune(it)).string()
	}
	return utf16_to_string(out.map(u16(it)))
}

fn vnbs_bare(s string, opts &VnbsOptions) string {
	mut result := vnbs_remove_strings(js_trim(s), opts.strings)
	for r in opts.regexps {
		result = vu4_regex_remove_all(&r.re, r.unicode, result)
	}
	return js_trim(result)
}

fn vnbs_target_attrs(tag string, opts &VnbsOptions, mut cache map[string][]string) []string {
	if cached := cache[tag] {
		return cached
	}
	mut out := []string{}
	if attrs := opts.attr_names[tag] {
		out << attrs
	}
	for r in opts.attr_regexps {
		if vue_regexp_test(&r.name, tag) {
			out << r.attrs
		}
	}
	if vue_is_kebab_case(tag) {
		out << vnbs_target_attrs(vue_pascal_case(tag), opts, mut cache)
	}
	cache[tag] = out
	return out
}

fn (mut c Checker) lint_vue_no_bare_strings_in_template(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.vue_has_template() {
		return []
	}
	sw := time.new_stopwatch()
	opts := vnbs_options(c.rule_options(vue_no_bare_strings_in_template))!
	mut findings := []Finding{}
	mut cache := map[string][]string{}
	mut stack := [][]string{}
	for step in c.vue_template_steps() {
		if step.node.kind != .vnode {
			continue
		}
		i := step.node.v
		node := &c.vue.doc.nodes[i]
		match node.typ {
			.v_element {
				if step.leave {
					if stack.len > 0 {
						stack.pop()
					}
				} else {
					stack << vnbs_target_attrs(node.raw_name, &opts, mut cache)
				}
			}
			.v_text {
				if step.leave {
					continue
				}
				stats.checked++
				if vnbs_bare(node.text, &opts) != '' {
					findings << c.vue_report_vnode(i, 'unexpected', map[string]string{})
				}
			}
			.v_attribute {
				if step.leave || stack.len == 0 || node.value < 0 {
					continue
				}
				stats.checked++
				if !node.directive {
					key := c.vue.doc.nodes[node.key].raw_name
					if key !in stack.last() {
						continue
					}
					if vnbs_bare(c.vue.doc.nodes[node.value].text, &opts) != '' {
						findings << c.vue_report_vnode(node.value, 'unexpectedInAttr', {
							'attr': key
						})
					}
					continue
				}
				directive := 'v-${c.vue_directive_name(i)}'
				if directive !in opts.directives {
					continue
				}
				e := c.vue.doc.nodes[node.value].expression
				if e.kind != .estree {
					continue
				}
				t := c.vue_expr_es(e)
				if t.typ(e.node) != .literal {
					continue
				}
				v := t.get(e.node, .value)
				if v is string {
					if v != '' && vnbs_bare(v, &opts) != '' {
						findings << c.vue_report_vnode(node.value, 'unexpectedInAttr', {
							'attr': directive
						})
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
