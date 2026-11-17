module rules

import jsregexp

// Port of eslint-plugin-vue 10.12.1's lib/utils/casing.ts: the case converters and checkers of the
// vue/* rules. The texts are handled as JavaScript strings (UTF-16 units: charAt, slice and the
// full Unicode toLowerCase and toUpperCase of V8, jsregexp's), the regular expressions of the
// original being of ASCII classes (`[A-Z]`, `\w`, `\B`) and of JavaScript white space (`\s`).

// vcase_is_symbol is the class of hasSymbols: /[!"#%&'()*+,./:;<=>?@[\\\]^`{|}]/u (without " ",
// "$", "-" and "_").
fn vcase_is_symbol(u u16) bool {
	return u < 0x80 && u8(u) in [`!`, `"`, `#`, `%`, `&`, `'`, `(`, `)`, `*`, `+`, `,`, `.`, `/`,
		`:`, `;`, `<`, `=`, `>`, `?`, `@`, `[`, `\\`, `]`, `^`, `\``, `{`, `|`, `}`]
}

fn vcase_has_symbols(s []u16) bool {
	return s.any(vcase_is_symbol(it))
}

fn vcase_is_upper(u u16) bool {
	return u >= `A` && u <= `Z`
}

fn vcase_is_lower(u u16) bool {
	return u >= `a` && u <= `z`
}

// vcase_is_word is `\w`.
fn vcase_is_word(u u16) bool {
	return vcase_is_upper(u) || vcase_is_lower(u) || (u >= `0` && u <= `9`) || u == `_`
}

fn vcase_has_upper(s []u16) bool {
	return s.any(vcase_is_upper(it))
}

// vcase_has_space is /\s/u.
fn vcase_has_space(s []u16) bool {
	return s.any(is_js_space(rune(it)))
}

fn vcase_contains(s []u16, sub string) bool {
	return utf16_to_string(s).contains(sub)
}

// vcase_boundary_upper is `.replaceAll(/\B([A-Z])/gu, sep + '$1')`: an uppercase letter after a
// word character (where there is no word boundary) gets `sep` before it.
fn vcase_boundary_upper(s []u16, sep u16) []u16 {
	mut out := []u16{cap: s.len + 4}
	for i, u in s {
		if i > 0 && vcase_is_upper(u) && vcase_is_word(s[i - 1]) {
			out << sep
		}
		out << u
	}
	return out
}

fn vcase_replace_unit(s []u16, from u16, to u16) []u16 {
	return s.map(if it == from { to } else { it })
}

// vue_capitalize is capitalize: the first unit upper-cased.
pub fn vue_capitalize(str string) string {
	s := utf16_units(str)
	if s.len == 0 {
		return ''
	}
	mut out := jsregexp.js_to_upper(s[..1])
	out << s[1..]
	return utf16_to_string(out)
}

// vue_kebab_case is kebabCase.
pub fn vue_kebab_case(str string) string {
	s := vcase_boundary_upper(vcase_replace_unit(utf16_units(str), `_`, `-`), `-`)
	return utf16_to_string(jsregexp.js_to_lower(s))
}

// vue_is_kebab_case is isKebabCase.
pub fn vue_is_kebab_case(str string) bool {
	s := utf16_units(str)
	return !vcase_has_upper(s) && !vcase_has_symbols(s) && !(s.len > 0 && s[0] == `-`)
		&& !vcase_contains(s, '_') && !vcase_contains(s, '--') && !vcase_has_space(s)
}

// vue_snake_case is snakeCase.
pub fn vue_snake_case(str string) string {
	s := vcase_replace_unit(vcase_boundary_upper(utf16_units(str), `_`), `-`, `_`)
	return utf16_to_string(jsregexp.js_to_lower(s))
}

// vue_is_snake_case is isSnakeCase.
pub fn vue_is_snake_case(str string) bool {
	s := utf16_units(str)
	return !vcase_has_upper(s) && !vcase_has_symbols(s) && !vcase_contains(s, '-')
		&& !vcase_contains(s, '__') && !vcase_has_space(s)
}

// vue_camel_case is camelCase.
pub fn vue_camel_case(str string) string {
	s := utf16_units(str)
	if vue_is_pascal_case(str) {
		if s.len == 0 {
			return ''
		}
		mut out := jsregexp.js_to_lower(s[..1])
		out << s[1..]
		return utf16_to_string(out)
	}
	// .replaceAll(/[-_](\w)/gu, (_, c) => c.toUpperCase())
	mut out := []u16{cap: s.len}
	mut i := 0
	for i < s.len {
		if (s[i] == `-` || s[i] == `_`) && i + 1 < s.len && vcase_is_word(s[i + 1]) {
			out << jsregexp.js_to_upper(s[i + 1..i + 2])
			i += 2
			continue
		}
		out << s[i]
		i++
	}
	return utf16_to_string(out)
}

// vue_is_camel_case is isCamelCase.
pub fn vue_is_camel_case(str string) bool {
	s := utf16_units(str)
	return !vcase_has_symbols(s) && !(s.len > 0 && vcase_is_upper(s[0])) && !vcase_contains(s, '-')
		&& !vcase_contains(s, '_') && !vcase_has_space(s)
}

// vue_pascal_case is pascalCase.
pub fn vue_pascal_case(str string) string {
	return vue_capitalize(vue_camel_case(str))
}

// vue_is_pascal_case is isPascalCase.
pub fn vue_is_pascal_case(str string) bool {
	s := utf16_units(str)
	return !vcase_has_symbols(s) && !(s.len > 0 && vcase_is_lower(s[0])) && !vcase_contains(s, '-')
		&& !vcase_contains(s, '_') && !vcase_has_space(s)
}

// vue_case_checker is getChecker (isPascalCase for an unknown case).
pub fn vue_case_check(name string, str string) bool {
	return match name {
		'kebab-case' { vue_is_kebab_case(str) }
		'snake_case' { vue_is_snake_case(str) }
		'camelCase' { vue_is_camel_case(str) }
		else { vue_is_pascal_case(str) }
	}
}

// vue_case_convert is getConverter (pascalCase for an unknown case).
pub fn vue_case_convert(name string, str string) string {
	return match name {
		'kebab-case' { vue_kebab_case(str) }
		'snake_case' { vue_snake_case(str) }
		'camelCase' { vue_camel_case(str) }
		else { vue_pascal_case(str) }
	}
}

// vue_case_exact_convert is getExactConverter: the conversion, or the text itself when the
// conversion is not in that case.
pub fn vue_case_exact_convert(name string, str string) string {
	result := vue_case_convert(name, str)
	return if vue_case_check(name, result) { result } else { str }
}
