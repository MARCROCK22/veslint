module rules

import json2

// Port of the `svelte/no-inner-declarations` rule of eslint-plugin-svelte 3.24.1: ESLint's
// no-inner-declarations (rules/no_inner_declarations.v) with its meta, on nodes whose parent is
// the Program when it is a SvelteScriptElement, which is how veslint's port reads a .svelte
// file's script (its statements are in the lint code's program). It has no conditions: it lints
// every file.

fn svnid_options(options []json2.Any) !NidOptions {
	return nid_options(options) or {
		return error(err.msg().replace('`${no_inner_declarations}`', '`${svelte_no_inner_declarations}`'))
	}
}

fn (mut c Checker) lint_svelte_no_inner_declarations(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return c.nid_lint(root, svnid_options(c.rule_options(svelte_no_inner_declarations))!, mut
		stats)
}
