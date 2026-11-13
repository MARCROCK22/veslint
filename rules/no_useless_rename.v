module rules

import json2
import time
import treesitter { named_children, node_field, node_kind, node_start, position_of }

// Port of the `no-useless-rename` rule of ESLint 10.6.0, with its options and its fix.

const nurn_messages = {
	'unnecessarilyRenamed': '{{type}} {{name}} unnecessarily renamed.'
}

struct NurOptions {
	ignore_destructuring bool
	ignore_import        bool
	ignore_export        bool
}

// nur_options reads ignoreDestructuring, ignoreImport and ignoreExport.
fn nur_options(options []json2.Any) !NurOptions {
	o := option_object(no_useless_rename, options, ['ignoreDestructuring', 'ignoreImport',
		'ignoreExport'])!
	return NurOptions{
		ignore_destructuring: o.bool_value('ignoreDestructuring')!
		ignore_import:        o.bool_value('ignoreImport')!
		ignore_export:        o.bool_value('ignoreExport')!
	}
}

fn (mut c Checker) lint_no_useless_rename(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nur_options(c.rule_options(no_useless_rename))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['object_pattern', 'import_specifier', 'export_specifier'], []) {
		stats.checked++
		match node_kind(node) {
			'object_pattern' {
				if o.ignore_destructuring {
					continue
				}
				for property in named_children(node) {
					if node_kind(property) != 'pair_pattern' {
						continue
					}
					key := node_field(property, 'key') or { continue }
					value := node_field(property, 'value') or { continue }
					// The key's name or string value (`key.value`, falsy for '').
					key_name := match node_kind(key) {
						'property_identifier' { c.identifier_name(key) }
						'string' { c.literal_name(key) or { '' } }
						else { '' }
					}
					if key_name == '' {
						continue
					}
					target := if node_kind(value) == 'assignment_pattern' {
						unwrap_parens(node_field(value, 'left') or { continue })
					} else {
						unwrap_parens(value)
					}
					if node_kind(target) !in ['identifier', 'undefined']
						|| c.identifier_name(target) != key_name {
						continue
					}
					replacement := if node_kind(value) == 'assignment_pattern' {
						value
					} else {
						unwrap_parens(value)
					}
					c.nur_report(root, property, replacement, key_name, 'Destructuring assignment', mut
						findings)
				}
			}
			'import_specifier' {
				if o.ignore_import {
					continue
				}
				imported := node_field(node, 'name') or { continue }
				local := node_field(node, 'alias') or { continue }
				name := c.nur_export_name(imported)
				if name == c.identifier_name(local) {
					c.nur_report(root, node, local, name, 'Import', mut findings)
				}
			}
			else {
				if o.ignore_export {
					continue
				}
				local := node_field(node, 'name') or { continue }
				exported := node_field(node, 'alias') or { continue }
				name := c.nur_export_name(local)
				if name == c.nur_export_name(exported) {
					c.nur_report(root, node, local, name, 'Export', mut findings)
				}
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// nur_export_name ports getModuleExportName: an identifier's name or a string's value.
fn (c &Checker) nur_export_name(n C.TSNode) string {
	if node_kind(n) == 'string' {
		return c.literal_name(n) or { '' }
	}
	return c.identifier_name(n)
}

// nur_report reports the node, with the fix that leaves the replacement alone: none when that
// would lose a comment or the parentheses of the target of a default value.
fn (mut c Checker) nur_report(root C.TSNode, node C.TSNode, replacement C.TSNode, name string, kind string, mut findings []Finding) {
	tokens := c.source_tokens(root)
	end := c.es_end(node)
	mut has_fix := tokens.comments_inside(node_start(node), end).len <= tokens.comments_inside(node_start(replacement),
		c.es_end(replacement)).len
	if node_kind(replacement) == 'assignment_pattern' {
		if left := node_field(replacement, 'left') {
			if node_kind(left) == 'parenthesized_expression' {
				has_fix = false
			}
		}
	}
	findings << Finding{
		stmt:       position_of(node)
		message_id: 'unnecessarilyRenamed'
		data:       {
			'name': name
			'type': kind
		}
		has_fix:    has_fix
		fix:        fix_replace_range(node_start(node), end, c.es_text(replacement))
	}
}
