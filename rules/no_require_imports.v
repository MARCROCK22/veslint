module rules

import json2
import jsregexp
import time
import treesitter { children, node_end, node_field, node_kind, node_parent, node_start, position_of }

// Port of the `no-require-imports` rule of typescript-eslint 8.62.0, with its options `allow`
// (patterns of the import paths that may be required, `new RegExp(pattern, 'u')`) and
// `allowAsImport`.

const nri_messages = {
	'noRequireImports': 'A `require()` style import is forbidden.'
}

struct NriOptions {
	allow           []jsregexp.RegexpProgram
	allow_as_import bool
}

fn nri_options(options []json2.Any) !NriOptions {
	o := option_object(no_require_imports, options, ['allow', 'allowAsImport'])!
	mut allow := []jsregexp.RegexpProgram{}
	for pattern in o.string_list('allow')! {
		allow << jsregexp.regexp_compile(pattern) or {
			return error('option `allow` of `${no_require_imports}`: ${err.msg()}')
		}
	}
	return NriOptions{
		allow:           allow
		allow_as_import: o.bool_value('allowAsImport')!
	}
}

fn (mut c Checker) lint_no_require_imports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nri_options(c.rule_options(no_require_imports))!
	mut findings := []Finding{}
	mut checked := 0
	for node in c.nodes_of_kinds(root, ['call_expression', 'import_require_clause'], []) {
		if node_kind(node) == 'import_require_clause' {
			// TSExternalModuleReference: the `require('…')` of `import x = require('…')`, whose
			// parent is always a TSImportEqualsDeclaration.
			keyword := children(node).filter(node_kind(it) == 'require')
			if keyword.len == 0 {
				continue
			}
			checked++
			if source := node_field(node, 'source') {
				if c.nri_is_allowed(o, source)! {
					continue
				}
			}
			if o.allow_as_import {
				continue
			}
			// The TSExternalModuleReference: `require(…)`, to its `)`.
			mut end := node_end(keyword[0])
			if clause := node_parent(keyword[0]) {
				for child in children(clause) {
					if node_kind(child) == ')' && node_start(child) >= end {
						end = node_end(child)
						break
					}
				}
			}
			findings << Finding{
				stmt:       c.position_range(node_start(keyword[0]), end)
				message_id: 'noRequireImports'
			}
			continue
		}
		// `CallExpression[callee.name="require"]`, also optional (`require?.('x')`); not a tagged
		// template.
		args := call_arguments(node) or { continue }
		callee := node_field(node, 'function') or { continue }
		inner := unwrap_parens(callee)
		if node_kind(inner) != 'identifier' || c.identifier_name(inner) != 'require' {
			continue
		}
		checked++
		if args.len > 0 && c.nri_is_allowed(o, args[0])! {
			continue
		}
		// A `require` declared in the file is something else than CommonJS's.
		tree := c.scope_tree(root)
		variable := tree.find_variable(tree.get_scope(node), 'require', -1)
		if variable >= 0 && tree.variables[variable].identifiers.len > 0 {
			continue
		}
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'noRequireImports'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += checked
	return findings
}

// nri_is_allowed: the argument is a string literal or a template literal whose static value
// (getStaticStringValue) one of the `allow` patterns matches (`importPath.match(pattern)`).
fn (c &Checker) nri_is_allowed(o NriOptions, argument C.TSNode) !bool {
	node := unwrap_parens(argument)
	if node_kind(node) !in ['string', 'template_string'] {
		return false
	}
	// A template with substitutions has no static value.
	value := c.literal_name(node) or { return false }
	for pattern in o.allow {
		matched := jsregexp.regexp_test(pattern, value) or {
			return error('option `allow` of `${no_require_imports}`: ${err.msg()}')
		}
		if matched {
			return true
		}
	}
	return false
}
