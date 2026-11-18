module rules

import estree
import json2
import os
import time

// Port of the `vue/match-component-file-name` rule of eslint-plugin-vue 10.12.1 (options
// `extensions`, by default ['jsx'], and `shouldMatchCase`): in a file with one of those
// extensions, a component name (`x.component('name', …)`, the `name` of a Vue object or of
// defineOptions) that is not the file's name, with a suggestion to rename it. A file with more
// than one component gets no report.

const vue_match_component_file_name_messages = {
	'shouldMatchFileName': 'Component name `{{name}}` should match file name `{{filename}}`.'
}

struct VmcfnOptions {
	extensions        []string
	should_match_case bool
}

fn vue_match_component_file_name_options(options []json2.Any) !VmcfnOptions {
	o := option_object(vue_match_component_file_name, options, ['extensions', 'shouldMatchCase'])!
	extensions := if 'extensions' in o.values { o.string_list('extensions')! } else { ['jsx'] }
	should_match_case := o.values['shouldMatchCase'] or { json2.Any(false) }
	return VmcfnOptions{
		extensions:        extensions
		should_match_case: should_match_case is bool && should_match_case
	}
}

fn (mut c Checker) lint_vue_match_component_file_name(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := vue_match_component_file_name_options(c.rule_options(vue_match_component_file_name))!
	mut findings := []Finding{}
	s := c.vue_script(root, abs_path) or { return findings }
	base := os.file_name(s.filename)
	extension := vmcfn_extname(base)
	if extension.trim_string_left('.') !in o.extensions {
		return findings
	}
	filename := base[..base.len - extension.len]
	t := c.es_tree(root, abs_path) or { return findings }
	mut name_nodes := []int{}
	mut component_count := 0
	for call in vue_call_component_calls(t) {
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 2 && vue_is_string_literal(t, args[0]) {
			name_nodes << args[0]
		}
	}
	for obj in s.objects_of(vue_all_object_types) {
		component_count++
		name := vue_find_property(t, obj, 'name', none)
		if name >= 0 && vue_is_string_literal(t, vue_property_value(t, name)) {
			name_nodes << vue_property_value(t, name)
		}
	}
	for call in c.vue_macros_named(t, 'defineOptions') {
		component_count++
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 0 || t.typ(args[0]) != .object_expression {
			continue
		}
		name := vue_find_property(t, args[0], 'name', none)
		if name >= 0 && vue_is_string_literal(t, vue_property_value(t, name)) {
			name_nodes << vue_property_value(t, name)
		}
	}
	if component_count > 1 {
		return findings
	}
	for node in name_nodes {
		stats.checked++
		name := vue_string_literal_value(t, node, false) or { continue }
		if vmcfn_equivalent(name, filename, o.should_match_case) {
			continue
		}
		findings << c.vmcfn_report(t, node, name, filename)
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vmcfn_extname is path.extname: from the last `.` of the name, unless it is its first character.
fn vmcfn_extname(base string) string {
	dot := base.last_index('.') or { return '' }
	return if dot <= 0 { '' } else { base[dot..] }
}

fn vmcfn_equivalent(name string, filename string, should_match_case bool) bool {
	return if should_match_case {
		name == filename
	} else {
		vue_pascal_case(name) == filename || vue_kebab_case(name) == filename
	}
}

fn (c &Checker) vmcfn_report(t &estree.EsTree, node int, name string, filename string) Finding {
	quote := if t.typ(node) == .template_literal {
		'`'
	} else {
		c.src[t.nodes[node].start].ascii_str()
	}
	return Finding{
		stmt:        c.es_tree_position(t, node)
		message_id:  'shouldMatchFileName'
		data:        {
			'filename': filename
			'name':     name
		}
		suggestions: [
			Suggestion{
				desc: 'Rename component to match file name.'
				fix:  fix_replace_range(t.nodes[node].start, t.nodes[node].end, '${quote}${filename}${quote}')
			},
		]
	}
}
