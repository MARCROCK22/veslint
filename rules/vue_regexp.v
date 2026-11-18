module rules

import jsregexp

// A port of eslint-plugin-vue 10.12.1's lib/utils/regexp.ts: the options of several vue/* rules
// are names or regular expressions written as strings (`"foo"` is /^foo$/, `"/^foo/i"` is /^foo/i).

// vue_regexp_str is RE_REGEXP_STR (/^\/(.+)\/(.*)$/u) on a string: the source and the flags when
// it is one. `.` does not take line terminators and `.+` is greedy: the last `/` ends the source.
fn vue_regexp_str(s string) ?(string, string) {
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

// vue_is_regexp is isRegExp.
fn vue_is_regexp(s string) bool {
	vue_regexp_str(s) or { return false }
	return true
}

// vue_regexp_escape is escape: the RegExp special characters get a backslash.
fn vue_regexp_escape(s string) string {
	mut out := []u8{cap: s.len}
	for ch in s {
		if ch in [`\\`, `^`, `$`, `.`, `*`, `+`, `?`, `(`, `)`, `[`, `]`, `{`, `}`, `|`] {
			out << `\\`
		}
		out << ch
	}
	return out.bytestr()
}

// vue_to_regexp is toRegExp(string, {add, remove}): a string like `/re/flags` is that regular
// expression (the flags in `add` or `remove` taken out, then those of `add` added), any other is
// /^string$/ with the flags of `add`. An error when JavaScript would throw.
fn vue_to_regexp(s string, add string, remove string) !jsregexp.JsRegex {
	if source, flags := vue_regexp_str(s) {
		mut kept := []u8{}
		for ch in flags {
			if !add.contains_u8(ch) && !remove.contains_u8(ch) {
				kept << ch
			}
		}
		return jsregexp.js_regex_new(source, kept.bytestr() + add)
	}
	return jsregexp.js_regex_new('^${vue_regexp_escape(s)}$', add)
}

// VueRegexpGroup is toRegExpGroupMatcher(patterns): whether any of the patterns matches any of the
// strings given to it (none when there are no patterns).
struct VueRegexpGroup {
	regexps []jsregexp.JsRegex
}

fn vue_regexp_group(patterns []string) !VueRegexpGroup {
	mut regexps := []jsregexp.JsRegex{}
	for p in patterns {
		regexps << vue_to_regexp(p, '', 'g')!
	}
	return VueRegexpGroup{
		regexps: regexps
	}
}

// matches is the matcher's call with the strings `to_check`.
fn (g &VueRegexpGroup) matches(to_check ...string) bool {
	for r in g.regexps {
		for s in to_check {
			if r.test(utf16_units(s)) or { false } {
				return true
			}
		}
	}
	return false
}

// vue_regexp_test is `regexp.test(s)` (false when the search fails).
fn vue_regexp_test(r &jsregexp.JsRegex, s string) bool {
	return r.test(utf16_units(s)) or { false }
}
