module rules

import jsregexp

// lib/utils/regexp.ts of eslint-plugin-vue 10.12.1: the options that take a name or a
// `/regexp/flags` string.

// vue_regexp_escape ports escape: the characters `\^$.*+?()[]{}|` with a backslash.
fn vue_regexp_escape(s string) string {
	mut out := []u8{cap: s.len}
	for b in s.bytes() {
		if b in [`\\`, `^`, `$`, `.`, `*`, `+`, `?`, `(`, `)`, `[`, `]`, `{`, `}`, `|`] {
			out << `\\`
		}
		out << b
	}
	return out.bytestr()
}

// vue_regexp_parts ports RE_REGEXP_STR (/^\/(.+)\/(.*)$/u): the pattern and the flags of a
// `/pattern/flags` string (`.` does not match line terminators).
fn vue_regexp_parts(s string) ?(string, string) {
	if s.len < 3 || s[0] != `/` {
		return none
	}
	for r in s.runes() {
		if r in [`\n`, `\r`, ` `, ` `] {
			return none
		}
	}
	last := s.last_index('/') or { return none }
	if last < 2 {
		return none
	}
	return s[1..last], s[last + 1..]
}

// vue_is_regexp ports isRegExp.
fn vue_is_regexp(s string) bool {
	return vue_regexp_parts(s) != none
}

// vue_to_regexp ports toRegExp with `{ remove }`: a `/pattern/flags` string without the removed
// flags, or the string itself, whole (`^…$`, escaped).
fn vue_to_regexp(s string, remove string) !jsregexp.JsRegex {
	if pattern, flags := vue_regexp_parts(s) {
		mut kept := ''
		for f in flags.runes() {
			if !remove.runes().contains(f) {
				kept += f.str()
			}
		}
		return jsregexp.js_regex_new(pattern, kept)!
	}
	return jsregexp.js_regex_new('^${vue_regexp_escape(s)}$', '')!
}

// VueRegexpGroup is toRegExpGroupMatcher's function: whether one of the patterns matches.
struct VueRegexpGroup {
	regexps []jsregexp.JsRegex
}

fn vue_regexp_group(patterns []string) !VueRegexpGroup {
	return VueRegexpGroup{
		regexps: patterns.map(vue_to_regexp(it, 'g')!)
	}
}

fn (g &VueRegexpGroup) test(s string) bool {
	units := utf16_units(s)
	for r in g.regexps {
		if r.test(units) or { false } {
			return true
		}
	}
	return false
}
