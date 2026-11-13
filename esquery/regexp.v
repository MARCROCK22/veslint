module esquery

import estree
import jsregexp

// Regular expressions of selectors (`[name=/re/i]`): esquery builds them with
// `new RegExp(pattern, flags)` (flags among `imsu`) and calls `test`; jsregexp.JsRegex does both
// as V8 does.

// compile_regex ports `new RegExp(pattern, flags)`.
fn compile_regex(pattern string, flags string) !jsregexp.JsRegex {
	return jsregexp.js_regex_new(pattern, flags)
}

// utf16_units are the UTF-16 code units of a (WTF-8) string.
fn utf16_units(s string) []u16 {
	return estree.utf16_units(s)
}
