module rules

import encoding.utf8
import json2
import jsregexp
import time
import treesitter { named_children, node_field, node_kind }

// Port of the `triple-slash-reference` rule of typescript-eslint 8.62.0, with its options `lib`
// ('always' or 'never'), `path` ('always' or 'never') and `types` ('always', 'never' or
// 'prefer-import').

const tsr_messages = {
	'tripleSlashReference': 'Do not use a triple slash reference for {{module}}, use `import` style instead.'
}

struct TsrOptions {
	lib   string
	path  string
	types string
}

fn tsr_options(options []json2.Any) !TsrOptions {
	o := option_object(triple_slash_reference, options, ['lib', 'path', 'types'])!
	return TsrOptions{
		lib:   o.string_value('lib', ['always', 'never'])!
		path:  o.string_value('path', ['always', 'never'])!
		types: o.string_value('types', ['always', 'never', 'prefer-import'])!
	}
}

// TsrReference is a `/// <reference types="…" />` comment that an import of the same module
// makes reported (types: 'prefer-import').
struct TsrReference {
	comment     SourceToken
	import_name string
}

fn (mut c Checker) lint_triple_slash_reference(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := tsr_options(c.rule_options(triple_slash_reference))!
	mut findings := []Finding{}
	if o.lib == 'always' && o.path == 'always' && o.types == 'always' {
		return findings
	}
	tokens := c.source_tokens(root)
	// The Program starts at its first token: the line comments before it.
	program_start := if tokens.tokens.len > 0 { tokens.tokens[0].start } else { c.src.len }
	mut references := []TsrReference{}
	mut checked := 0
	for comment in tokens.comments_before(program_start) {
		if comment.kind != .line_comment {
			continue
		}
		checked++
		kind, name := tsr_match(c.src[comment.start + 2..comment.end]) or { continue }
		if (kind == 'types' && o.types == 'never') || (kind == 'path' && o.path == 'never')
			|| (kind == 'lib' && o.lib == 'never') {
			findings << c.tsr_finding(comment, name)
			continue
		}
		if kind == 'types' && o.types == 'prefer-import' {
			references << TsrReference{
				comment:     comment
				import_name: name
			}
		}
	}
	if references.len > 0 {
		// An ImportDeclaration, or a TSImportEqualsDeclaration with a TSExternalModuleReference,
		// reports each reference to its module, every time.
		for node in c.nodes_of_kind(root, c'import_statement') {
			source := c.tsr_module_source(node) or { continue }
			raw := c.text(source)
			value := cooked_string(raw[1..raw.len - 1], false) or { continue }
			for reference in references {
				if reference.import_name == value {
					findings << c.tsr_finding(reference.comment, reference.import_name)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

fn (c &Checker) tsr_finding(comment SourceToken, name string) Finding {
	return Finding{
		stmt:       c.position_range(comment.start, comment.end)
		message_id: 'tripleSlashReference'
		data:       {
			'module': name
		}
	}
}

// tsr_module_source is the string an import takes its module from: the source of an
// ImportDeclaration, or the string of `require()` in a TSImportEqualsDeclaration (with `export`
// too, the declaration of its export statement).
fn (c &Checker) tsr_module_source(node C.TSNode) ?C.TSNode {
	for child in named_children(node) {
		if node_kind(child) == 'import_require_clause' {
			for part in named_children(child) {
				if node_kind(part) == 'string' {
					return part
				}
			}
			return none
		}
	}
	return node_field(node, 'source')
}

// tsr_match ports /^\/\s*<reference\s*(types|path|lib)\s*=\s*["|'](.*)["|']/ on the value of a
// line comment: the kind of reference, and what is between the first quote and the last quote
// (or `|`) before the end of the line.
fn tsr_match(value string) ?(string, string) {
	if !value.starts_with('/') {
		return none
	}
	mut i := tsr_skip_space(value, 1)
	if !value[i..].starts_with('<reference') {
		return none
	}
	i = tsr_skip_space(value, i + '<reference'.len)
	mut kind := ''
	for candidate in ['types', 'path', 'lib'] {
		if value[i..].starts_with(candidate) {
			kind = candidate
			break
		}
	}
	if kind == '' {
		return none
	}
	i = tsr_skip_space(value, i + kind.len)
	if i >= value.len || value[i] != `=` {
		return none
	}
	i = tsr_skip_space(value, i + 1)
	if i >= value.len || value[i] !in [`"`, `|`, `'`] {
		return none
	}
	start := i + 1
	// `.` stops at a line terminator.
	mut end := value.len
	for j := start; j < value.len; j++ {
		if value[j] in [`\n`, `\r`] || (value[j] == 0xe2 && j + 2 < value.len && value[j + 1] == 0x80
			&& value[j + 2] in [u8(0xa8), 0xa9]) {
			end = j
			break
		}
	}
	mut last := -1
	for j in start .. end {
		if value[j] in [`"`, `|`, `'`] {
			last = j
		}
	}
	if last < 0 {
		return none
	}
	return kind, value[start..last]
}

// tsr_skip_space skips the white space and line terminators (`\s`) from byte `i`.
fn tsr_skip_space(value string, i int) int {
	mut j := i
	for j < value.len {
		r := utf8.get_rune(value, j)
		if !tsr_is_space(u32(r)) {
			break
		}
		j += utf8_char_len(value[j])
	}
	return j
}

fn tsr_is_space(r u32) bool {
	for k := 0; k < jsregexp.rx_space.len; k += 2 {
		if r >= jsregexp.rx_space[k] && r <= jsregexp.rx_space[k + 1] {
			return true
		}
	}
	return false
}
