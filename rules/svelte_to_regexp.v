module rules

import jsregexp

// toRegExp of eslint-plugin-svelte 3.24.1's utils/regexp.ts (prefix `svrx_`): a string like
// `/re/flags` is that regular expression, any other matches only itself.

// SvrxMatcher is toRegExp's result: `{ test }`.
struct SvrxMatcher {
	exact    string
	is_regex bool
	re       jsregexp.JsRegex
}

// svrx_parts is RE_REGEXP_STR (/^\/(.+)\/([A-Za-z]*)$/u) on a string: the source and the flags.
fn svrx_parts(s string) ?(string, string) {
	if s.len < 3 || s[0] != `/` {
		return none
	}
	last := s.last_index('/') or { return none }
	if last < 2 {
		return none
	}
	flags := s[last + 1..]
	for ch in flags {
		if !ch.is_letter() {
			return none
		}
	}
	source := s[1..last]
	// `.` takes no line terminator.
	if source.contains_any('\n\r') || source.contains(' ') || source.contains(' ') {
		return none
	}
	return source, flags
}

// svrx_to_regexp is toRegExp: an error when `new RegExp` throws. The `g` and `y` flags are left
// out: they only make `test` remember where the last match ended.
fn svrx_to_regexp(s string) !SvrxMatcher {
	if source, flags := svrx_parts(s) {
		return SvrxMatcher{
			is_regex: true
			re:       jsregexp.js_regex_new(source, flags.replace('g', '').replace('y', ''))!
		}
	}
	return SvrxMatcher{
		exact: s
	}
}

fn (m &SvrxMatcher) test(s string) bool {
	if !m.is_regex {
		return s == m.exact
	}
	return m.re.test(utf16_units(s)) or { false }
}
