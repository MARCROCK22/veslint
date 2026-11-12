module rules

import json2
import time
import treesitter { node_field, node_kind, node_parent, position_of }

// Port of the `no-namespace` rule of typescript-eslint 8.62.0, with its options
// `allowDeclarations` and `allowDefinitionFiles`.

const nn_messages = {
	'moduleSyntaxIsPreferred': 'ES2015 module syntax is preferred over namespaces.'
}

struct NnOptions {
	allow_declarations     bool
	allow_definition_files bool
}

fn nn_options(options []json2.Any) !NnOptions {
	o := option_object(no_namespace, options, ['allowDeclarations', 'allowDefinitionFiles'])!
	return NnOptions{
		allow_declarations:     o.bool_value('allowDeclarations')!
		allow_definition_files: o.bool_value('allowDefinitionFiles')!
	}
}

fn (mut c Checker) lint_no_namespace(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nn_options(c.rule_options(no_namespace))!
	mut findings := []Finding{}
	mut checked := 0
	// `TSModuleDeclaration[global!=true][id.type!='Literal']`: `namespace X {}` and `module X {}`,
	// not `declare global {}` (no module node in tree-sitter) nor `declare module 'x' {}`.
	if o.allow_definition_files && is_definition_file(abs_path) {
		return findings
	}
	for node in c.nodes_of_kinds(root, ['internal_module', 'module'], []) {
		name := node_field(node, 'name') or { continue }
		if node_kind(name) == 'string' {
			continue
		}
		checked++
		if o.allow_declarations && nn_is_declaration(node) {
			continue
		}
		// A declared module starts at its `declare`.
		parent := node_parent(node) or { node }
		reported := if node_kind(parent) == 'ambient_declaration' { parent } else { node }
		findings << Finding{
			stmt:       position_of(reported)
			message_id: 'moduleSyntaxIsPreferred'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nn_is_declaration ports isDeclaration: the module, or a module around it, is declared
// (`declare namespace X {}`, `declare module 'x' {}`, `declare global {}`, which tree-sitter has
// as an ambient_declaration without a module node). Nothing else that is declared can hold a
// namespace.
fn nn_is_declaration(n C.TSNode) bool {
	mut node := n
	for {
		node = node_parent(node) or { return false }
		if node_kind(node) == 'ambient_declaration' {
			return true
		}
	}
	return false
}

// is_definition_file ports isDefinitionFile: a `.d.ts`, `.d.cts` or `.d.mts` file, or one named
// like `x.d.css.ts`.
fn is_definition_file(file_name string) bool {
	lower := file_name.to_lower()
	if lower.ends_with('.d.ts') || lower.ends_with('.d.cts') || lower.ends_with('.d.mts') {
		return true
	}
	// /\\.d\\.(ts|cts|mts|.*\\.ts)$/: `.d.` and then anything that ends in `.ts`.
	i := lower.last_index('.d.') or { return false }
	return lower[i + 3..].ends_with('.ts')
}
