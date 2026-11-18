module rules

// Port of the `svelte/no-export-load-in-svelte-module-in-kit-pages` rule of eslint-plugin-svelte
// 3.24.1: in a SvelteKit page, layout or error component, the name of an exported `load` function
// or variable of the module script (`<script module>`, `<script context="module">`) is reported.

const svnelisvmikp_messages = {
	'unexpected': 'disallow exporting load functions in `*.svelte` module in SvelteKit page components.'
}

fn (mut c Checker) lint_svelte_no_export_load_in_svelte_module_in_kit_pages(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte()
		|| c.svsc_kit_file_type(abs_path) !in [.page_svelte, .error_svelte, .layout_svelte] {
		return []
	}
	es := &c.svelte.doc.es
	mut findings := []Finding{}
	for step in c.sv_steps() {
		if step.leave || !step.node.es {
			continue
		}
		i := step.node.idx
		if es.typ(i) != .identifier || (es.string_of(i, .name) or { '' }) != 'load' {
			continue
		}
		parent := es.nodes[i].parent
		if parent < 0 || (es.node(parent, .id) or { -1 }) != i {
			continue
		}
		mut export := -1
		if es.typ(parent) == .function_declaration {
			export = es.nodes[parent].parent
		} else if es.typ(parent) == .variable_declarator {
			declaration := es.nodes[parent].parent
			if declaration >= 0 && es.typ(declaration) == .variable_declaration {
				export = es.nodes[declaration].parent
			}
		}
		if export < 0 || es.typ(export) != .export_named_declaration {
			continue
		}
		script := c.svsc_script_of(es.nodes[i].start)
		if script >= 0 && c.sv_is_module_script(script) {
			findings << c.sv_report_es(i, 'unexpected', {})
		}
	}
	return findings
}
