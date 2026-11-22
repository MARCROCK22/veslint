module rules

// Port of the `svelte/valid-style-parse` rule of eslint-plugin-svelte 3.24.1: at each <style>
// element, the error of parsing the first one (postcss, or postcss-scss for lang="scss"; the
// current directory taken out of the error's path), or its unknown lang.

const svsp_messages = map[string]string{}

fn (mut c Checker) lint_svelte_valid_style_parse(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	styles := c.sv_snodes_of(.style_element)
	if styles.len == 0 {
		return []
	}
	ctx := c.svst_style_context(abs_path)
	mut findings := []Finding{}
	for s in styles {
		end := c.sv_snode_loc_end(s)
		if ctx.status == .parse_error {
			findings << c.sv_report_message(doc.nodes[s].start, end, 'Error parsing style element. Error message: "${svst_parse_error_message(ctx.error)}"')
		}
		if ctx.status == .unknown_lang {
			findings << c.sv_report_message(doc.nodes[s].start, end, 'Found unsupported style element language "${ctx.lang}"')
		}
	}
	return findings
}
