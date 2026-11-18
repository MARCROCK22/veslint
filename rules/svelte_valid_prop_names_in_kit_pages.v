module rules

// Port of the `svelte/valid-prop-names-in-kit-pages` rule of eslint-plugin-svelte 3.24.1: in a
// SvelteKit page, layout or error component, the instance script's props must be those SvelteKit
// passes: `export let` declarations (Svelte 3/4 style, checked with Svelte 5 too) and the
// properties destructured from `$props()` (Svelte 5: those of the file type).

const svvpnikp_messages = {
	'unexpected': 'disallow invalid props in SvelteKit route components.'
}

const svvpnikp_page_props = ['data', 'form', 'params', 'snapshot']
const svvpnikp_legacy_page_props = ['data', 'form', 'params', 'snapshot', 'errors']
const svvpnikp_layout_props = ['data', 'form', 'params', 'snapshot', 'children']
const svvpnikp_error_props = ['error']

// svvpnikp_check_prop is checkProp: the keys of an object pattern that are not expected.
fn (c &Checker) svvpnikp_check_prop(declarator int, expected []string, mut findings []Finding) {
	es := &c.svelte.doc.es
	id := es.node(declarator, .id) or { return }
	if es.typ(id) != .object_pattern {
		return
	}
	for p in es.list(id, .properties) or { []int{} } {
		if es.typ(p) != .property {
			continue
		}
		key := es.node(p, .key) or { continue }
		if es.typ(key) == .identifier && (es.string_of(key, .name) or { '' }) !in expected {
			findings << c.sv_report_es(key, 'unexpected', {})
		}
	}
}

fn (mut c Checker) lint_svelte_valid_prop_names_in_kit_pages(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	file_type := c.svsc_kit_file_type(abs_path)
	if file_type !in [.page_svelte, .layout_svelte, .error_svelte] {
		return []
	}
	expected := match file_type {
		.layout_svelte { svvpnikp_layout_props }
		.error_svelte { svvpnikp_error_props }
		else { svvpnikp_page_props }
	}
	es := &c.svelte.doc.es
	mut findings := []Finding{}
	for step in c.sv_steps() {
		if step.leave || !step.node.es || es.typ(step.node.idx) != .variable_declarator {
			continue
		}
		i := step.node.idx
		script := c.svsc_script_of(es.nodes[i].start)
		if script < 0 || c.sv_is_module_script(script) {
			continue
		}
		declaration := es.nodes[i].parent
		if declaration < 0 || es.typ(declaration) != .variable_declaration {
			continue
		}
		export := es.nodes[declaration].parent
		if export >= 0 && es.typ(export) == .export_named_declaration {
			id := es.node(i, .id) or { -1 }
			if id >= 0 && es.typ(id) == .identifier {
				if (es.string_of(id, .name) or { '' }) !in svvpnikp_legacy_page_props {
					findings << c.sv_report_es(i, 'unexpected', {})
				}
			} else {
				c.svvpnikp_check_prop(i, svvpnikp_legacy_page_props, mut findings)
			}
		}
		init := es.node(i, .init) or { continue }
		if es.typ(init) != .call_expression {
			continue
		}
		callee := es.node(init, .callee) or { continue }
		if es.typ(callee) != .identifier || (es.string_of(callee, .name) or { '' }) != '\$props' {
			continue
		}
		c.svvpnikp_check_prop(i, expected, mut findings)
	}
	return findings
}
