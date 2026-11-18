module rules

import json2
import svelte_compiler

// Port of the `svelte/valid-compile` rule of eslint-plugin-svelte 3.24.1: the Svelte compiler's
// warnings (and its error) for the file, from svelte_compile_warns.v. `ignoreWarnings` reports only
// an error. The `missing-declaration` code (Svelte 3/4) is skipped, and so are unused selectors in
// a <style global>. svelte.config.js's onwarn/warningFilter are not read (svelte_compile_warns.v).

fn svc_valid_compile_options(options []json2.Any) !bool {
	o := option_object(svelte_valid_compile, options, ['ignoreWarnings'])!
	return o.bool_value('ignoreWarnings')!
}

fn (mut c Checker) lint_svelte_valid_compile(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	ignore_warnings := svc_valid_compile_options(c.rule_options(svelte_valid_compile))!
	if !c.is_svelte() {
		return []
	}
	doc := c.svelte.doc
	// The <style global> elements (an attribute named `global`).
	mut global_styles := [][]int{}
	for child in c.svelte_program_body() {
		n := doc.nodes[child]
		if n.typ == .style_element {
			tag := c.sv_start_tag(child)
			for a in doc.nodes[tag].attributes {
				if doc.nodes[a].typ == .attribute && c.sv_attribute_name(a) == 'global' {
					global_styles << [n.start, n.end]
					break
				}
			}
		}
	}
	result := c.svc_warnings()
	if ignore_warnings && !result.is_error {
		return []
	}
	no_pos := svelte_compiler.no_pos
	mut findings := []Finding{}
	for w in result.warnings {
		if w.code != '' {
			if w.code == 'missing-declaration' {
				continue
			}
			if w.code in ['css_unused_selector', 'css-unused-selector'] && w.start != no_pos
				&& w.end != no_pos && global_styles.any(it[0] <= w.start && w.end <= it[1]) {
				continue
			}
		}
		start := if w.start != no_pos {
			w.start
		} else if w.end != no_pos {
			w.end
		} else {
			0
		}
		end := if w.end != no_pos {
			w.end
		} else if w.start != no_pos {
			w.start
		} else {
			0
		}
		message := w.message + if w.code != '' { '(${w.code})' } else { '' }
		findings << Finding{
			...c.sv_report_message(start, end, message)
			text_loc: result.transformed
		}
	}
	return findings
}
