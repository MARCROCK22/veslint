module rules

// Port of the `svelte/experimental-require-strict-events` rule of eslint-plugin-svelte 3.24.1: a
// TypeScript component needs the strictEvents attribute on its (last) <script> or a $$Events
// interface or type. Its condition is Svelte 3/4: with the Svelte 5 eslint-plugin-svelte is
// tested with (svelte_compiler_major), it reports nothing.

const serse_messages = {
	'missingStrictEvents': 'The component must have the strictEvents attribute on its <script> tag or it must define the \$\$Events interface.'
}

// svelte_compiler_major is the major version of svelte/compiler eslint-plugin-svelte's conditions
// compare with (getSvelteContext's svelteVersion).
const svelte_compiler_major = 5

fn (mut c Checker) lint_svelte_experimental_require_strict_events(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() || svelte_compiler_major >= 5 {
		return []
	}
	mut is_ts := false
	mut has_attribute := false
	mut script := -1
	for i in c.sv_snodes_of(.script_element) {
		lang := (c.sv_lang_value(i) or { '' }).to_lower()
		is_ts = lang == 'ts' || lang == 'typescript'
		has_attribute = c.sv_find_attribute(i, 'strictEvents') >= 0
		script = i
	}
	if !is_ts || has_attribute || c.serst_declares_type('\$\$Events') || script < 0 {
		return []
	}
	return [c.sv_report_snode(script, 'missingStrictEvents', {})]
}
