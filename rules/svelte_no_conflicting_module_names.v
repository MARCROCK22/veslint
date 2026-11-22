module rules

import os

// Port of the `svelte/no-conflicting-module-names` rule of eslint-plugin-svelte 3.24.1: a component
// `Foo.svelte` and a module `Foo.svelte.<ext>` (an extension TypeScript appends to an unknown
// `./Foo.svelte` import: not `.d.ts`) beside it collide; each side reports on itself at line 1,
// column 0 (no end). Only files on disk are checked. It has no conditions: it lints every file.

const svncmn_messages = {
	'conflictOnComponent': 'The module `{{moduleName}}` has the same name as this component. TypeScript resolves the import `{{specifier}}` to that module, not to this component. Rename `{{moduleName}}`.'
	'conflictOnModule':    'This module has the same name as the component `{{svelteName}}`. TypeScript resolves the import `{{specifier}}` to this module, not to the component. Rename this file.'
}

const svncmn_extensions = ['.ts', '.tsx', '.js', '.jsx', '.mts', '.cts', '.mjs', '.cjs']

// svncmn_real_basename is realBasename: the directory's entry with that name, else one equal to it
// ignoring case, else the name.
fn svncmn_real_basename(path string) string {
	wanted := os.file_name(path)
	entries := os.ls(os.dir(path)) or { return wanted }
	if wanted in entries {
		return wanted
	}
	lower := wanted.to_lower()
	for entry in entries {
		if entry.to_lower() == lower {
			return entry
		}
	}
	return wanted
}

// svncmn_report is a report at `{ line: 1, column: 0 }`, without an end.
fn (c &Checker) svncmn_report(message_id string, data map[string]string) Finding {
	return Finding{
		stmt:         c.position_range(0, 0)
		message_id:   message_id
		data:         data
		fixed_line:   1
		fixed_column: 1
		no_end:       true
	}
}

fn (mut c Checker) lint_svelte_no_conflicting_module_names(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	path := c.sv_file_path(abs_path)
	if path.ends_with('.svelte') {
		if !os.is_file(path) {
			return []
		}
		for ext in svncmn_extensions {
			module_path := path + ext
			if os.is_file(module_path) {
				return [
					c.svncmn_report('conflictOnComponent', {
						'moduleName': svncmn_real_basename(module_path)
						'specifier':  './${os.file_name(path)}'
					}),
				]
			}
		}
		return []
	}
	mut svelte_path := ''
	for ext in svncmn_extensions {
		if path.ends_with(ext) {
			svelte_path = path[..path.len - ext.len]
			break
		}
	}
	if !svelte_path.ends_with('.svelte') || !os.is_file(svelte_path) || !os.is_file(path) {
		return []
	}
	svelte_name := svncmn_real_basename(svelte_path)
	return [
		c.svncmn_report('conflictOnModule', {
			'svelteName': svelte_name
			'specifier':  './${svelte_name}'
		}),
	]
}
