module rules

import jsregexp

// The `ignore` package 5.3.2 (the gitignore rules ESLint's no-restricted-imports gives its
// `group` patterns), as Ignore#ignores answers on Linux: each pattern becomes a regular expression
// through the package's REPLACERS, which run here as String.prototype.replace with the same
// regular expressions (regexp_match.v, whose `u` mode reads them as V8 reads them without flags,
// as they only use ASCII), and the source they give is compiled without flags (or with `i`, as a
// modifier) by regexp_annex_b.v. A path is ignored when its last matching rule is not negated,
// or when one of its parent directories is.

struct GitignoreRule {
	negative bool
	program  jsregexp.RegexpProgram
}

struct Gitignore {
mut:
	rules []GitignoreRule
	cache map[string]GitignoreResult
}

struct GitignoreResult {
	ignored   bool
	unignored bool
}

// gitignore_replace ports `text.replace(regex, replacer)`: every match (the first only without
// `global`) is replaced by what the replacer gives for the match, its groups (none for one that
// did not take part) and its index (in UTF-16 units, as the patterns are ASCII here).
fn gitignore_replace(text string, pattern string, global bool, replacer fn (string, []?string, int, string) string) string {
	program := jsregexp.regexp_compile(pattern) or { return text }
	input := text.runes()
	mut out := []rune{}
	mut from := 0
	mut last := 0
	for from <= input.len {
		found, start, end, groups := jsregexp.regexp_exec(program, input, from) or { break }
		if !found {
			break
		}
		out << input[last..start]
		mut captures := []?string{}
		for g in 1 .. groups.len / 2 {
			a := groups[2 * g]
			b := groups[2 * g + 1]
			captures << if a >= 0 && b >= 0 { ?string(input[a..b].string()) } else { ?string(none) }
		}
		out << replacer(input[start..end].string(), captures, utf16_units(input[..start].string()).len,
			text).runes()
		last = end
		if !global {
			break
		}
		from = if end == start { end + 1 } else { end }
	}
	if last < input.len {
		out << input[last..]
	}
	return out.string()
}

fn gitignore_group(groups []?string, i int) string {
	return groups[i] or { '' }
}

// gitignore_source ports makeRegex: the source of the regular expression of a pattern.
fn gitignore_source(pattern string) string {
	mut s := pattern
	// remove BOM
	s = gitignore_replace(s, '^\\uFEFF', false, fn (m string, g []?string, i int, t string) string {
		return ''
	})
	// Trailing spaces are ignored unless they are quoted with backslash.
	s = gitignore_replace(s, '((?:\\\\\\\\)*?)(\\\\?\\s+)$', false, fn (m string, g []?string, i int, t string) string {
		return gitignore_group(g, 0) + if gitignore_group(g, 1).starts_with('\\') {
			' '
		} else {
			''
		}
	})
	// (\ ) -> ' '
	s = gitignore_replace(s, '(\\\\+?)\\s', true, fn (m string, g []?string, i int, t string) string {
		m1 := gitignore_group(g, 0)
		return m1[..m1.len - m1.len % 2] + ' '
	})
	// Escape metacharacters.
	s = gitignore_replace(s, '[\\\\$.|*+(){^]', true, fn (m string, g []?string, i int, t string) string {
		return '\\${m}'
	})
	s = gitignore_replace(s, '(?!\\\\)\\?', true, fn (m string, g []?string, i int, t string) string {
		return '[^/]'
	})
	// leading slash
	s = gitignore_replace(s, '^\\/', false, fn (m string, g []?string, i int, t string) string {
		return '^'
	})
	// replace special metacharacter slash after the leading slash
	s = gitignore_replace(s, '\\/', true, fn (m string, g []?string, i int, t string) string {
		return '\\/'
	})
	// leading `**/`
	s = gitignore_replace(s, '^\\^*\\\\\\*\\\\\\*\\\\\\/', false, fn (m string, g []?string, i int, t string) string {
		return '^(?:.*\\/)?'
	})
	// starting: `this` is the pattern
	starting := if gitignore_has_inner_slash(pattern) { '^' } else { '(?:^|\\/)' }
	s = gitignore_replace(s, '^(?=[^^])', false, fn [starting] (m string, g []?string, i int, t string) string {
		return starting
	})
	// two globstars
	s = gitignore_replace(s, '\\\\\\/\\\\\\*\\\\\\*(?=\\\\\\/|$)', true, fn (m string, g []?string, i int, t string) string {
		return if i + 6 < utf16_units(t).len { '(?:\\/[^\\/]+)*' } else { '\\/.+' }
	})
	// normal intermediate wildcards
	s = gitignore_replace(s, '(^|[^\\\\]+)(\\\\\\*)+(?=.+)', true, fn (m string, g []?string, i int, t string) string {
		// p2 is the last iteration of the group: a run of `\*` becomes one wildcard.
		return gitignore_group(g, 0) + gitignore_group(g, 1).replace('\\*', '[^\\/]*')
	})
	// unescape, revert step 3 except for back slash
	s = gitignore_replace(s, '\\\\\\\\\\\\(?=[$.|*+(){^])', true, fn (m string, g []?string, i int, t string) string {
		return '\\'
	})
	s = gitignore_replace(s, '\\\\\\\\', true, fn (m string, g []?string, i int, t string) string {
		return '\\'
	})
	// ranges
	s = gitignore_replace(s, '(\\\\)?\\[([^\\]/]*?)(\\\\*)($|\\])', true, fn (m string, g []?string, i int, t string) string {
		lead := g[0] or { '' }
		range := gitignore_group(g, 1)
		end_escape := gitignore_group(g, 2)
		close := gitignore_group(g, 3)
		if lead == '\\' {
			return '\\[${range}${end_escape[..end_escape.len - end_escape.len % 2]}${close}'
		}
		if close == ']' {
			if end_escape.len % 2 == 0 {
				return '[${gitignore_sanitize_range(range)}${end_escape}]'
			}
			return '[]'
		}
		return '[]'
	})
	// ending
	s = gitignore_replace(s, '(?:[^*])$', false, fn (m string, g []?string, i int, t string) string {
		return if m.ends_with('/') { '${m}$' } else { '${m}(?=$|\\/$)' }
	})
	// trailing wildcard
	s = gitignore_replace(s, '(\\^|\\\\\\/)?\\\\\\*$', false, fn (m string, g []?string, i int, t string) string {
		p1 := gitignore_group(g, 0)
		prefix := if p1 != '' { '${p1}[^/]+' } else { '[^/]*' }
		return '${prefix}(?=$|\\/$)'
	})
	return s
}

// gitignore_has_inner_slash ports /\/(?!$)/.test(pattern).
fn gitignore_has_inner_slash(pattern string) bool {
	for i, ch in pattern {
		if ch == `/` && i + 1 < pattern.len {
			return true
		}
	}
	return false
}

// gitignore_sanitize_range ports sanitizeRange: a range out of order is removed.
fn gitignore_sanitize_range(range string) string {
	return gitignore_replace(range, '([0-z])-([0-z])', true, fn (m string, g []?string, i int, t string) string {
		from := gitignore_group(g, 0)
		to := gitignore_group(g, 1)
		return if from[0] <= to[0] { m } else { '' }
	})
}

// new_gitignore ports `ignore({allowRelativePaths: true, ignorecase}).add(patterns)`.
fn new_gitignore(patterns []string, ignore_case bool) Gitignore {
	mut out := Gitignore{}
	for item in patterns {
		for line0 in item.split('\n') {
			line := line0.trim_string_right('\r')
			if !gitignore_check_pattern(line) {
				continue
			}
			mut pattern := line
			mut negative := false
			if pattern.starts_with('!') {
				negative = true
				pattern = pattern[1..]
			}
			if pattern.starts_with('\\!') {
				pattern = '!' + pattern[2..]
			}
			if pattern.starts_with('\\#') {
				pattern = '#' + pattern[2..]
			}
			source := gitignore_source(pattern)
			text := if ignore_case { '(?i:${source})' } else { source }
			program := jsregexp.regexp_compile_annex_b(utf16_units(text)) or { continue }
			out.rules << GitignoreRule{
				negative: negative
				program:  program
			}
		}
	}
	return out
}

// gitignore_check_pattern ports checkPattern: not empty, not blank, no invalid trailing backslash
// and not a comment.
fn gitignore_check_pattern(pattern string) bool {
	if pattern == '' || pattern.starts_with('#') {
		return false
	}
	if pattern.runes().all(is_js_space(it)) {
		return false
	}
	// /(?:[^\\]|^)\\$/
	if pattern.ends_with('\\') && (pattern.len == 1 || pattern[pattern.len - 2] != `\\`) {
		return false
	}
	return true
}

fn (g &Gitignore) test_one(path string) GitignoreResult {
	mut ignored := false
	mut unignored := false
	for rule in g.rules {
		if (unignored == rule.negative && ignored != unignored)
			|| (rule.negative && !ignored && !unignored) {
			continue
		}
		if jsregexp.regexp_test_annex_b(rule.program, utf16_units(path)) or { false } {
			ignored = !rule.negative
			unignored = rule.negative
		}
	}
	return GitignoreResult{ignored, unignored}
}

// ignores ports Ignore#ignores: the path, or a parent directory of it, is ignored.
fn (mut g Gitignore) ignores(path string) bool {
	return g.test(path, path.split('/')).ignored
}

fn (mut g Gitignore) test(path string, slices0 []string) GitignoreResult {
	if result := g.cache[path] {
		return result
	}
	mut slices := slices0.clone()
	slices.pop()
	if slices.len == 0 {
		result := g.test_one(path)
		g.cache[path] = result
		return result
	}
	parent := g.test(slices.join('/') + '/', slices)
	result := if parent.ignored { parent } else { g.test_one(path) }
	g.cache[path] = result
	return result
}
