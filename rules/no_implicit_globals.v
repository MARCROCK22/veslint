module rules

import json2
import time
import treesitter { node_kind, node_parent, position_of }

// Port of the `no-implicit-globals` rule of ESLint 10.6.0.

const nig_messages = {
	'globalNonLexicalBinding':       'Unexpected {{kind}} declaration in the global scope, wrap in an IIFE for a local variable, assign as global property for a global variable.'
	'globalLexicalBinding':          'Unexpected {{kind}} declaration in the global scope, wrap in a block or in an IIFE.'
	'globalVariableLeak':            'Global variable leak, declare the variable if it is intended to be local.'
	'assignmentToReadonlyGlobal':    'Unexpected assignment to read-only global variable.'
	'redeclarationOfReadonlyGlobal': 'Unexpected redeclaration of read-only global variable.'
}

fn nig_options(options []json2.Any) !bool {
	o := option_object(no_implicit_globals, options, ['lexicalBindings'])!
	return o.bool_value('lexicalBindings') or { false }
}

fn (mut c Checker) lint_no_implicit_globals(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	lexical_bindings := nig_options(c.rule_options(no_implicit_globals))!
	tree := c.scope_tree(root)
	mut findings := []Finding{}
	for v in tree.scopes[0].variables {
		stats.checked++
		variable := tree.variables[v]
		// Only the globals ESLint declares (configuration, ecmaVersion or comment) and
		// typescript-eslint's lib variables (not writable) have `writeable`.
		has_writeable := variable.lib || variable.eslint_implicit_global_setting != ''
			|| variable.eslint_explicit_global
		readonly := has_writeable && !variable.writeable
		if has_writeable && variable.writeable {
			continue
		}
		if variable.eslint_used {
			continue
		}
		for def in variable.defs {
			mut kind := ''
			mut lexical := false
			if def.kind == .function_name {
				kind = 'function'
			} else if def.kind == .variable && def.parent_kind == 'var' {
				kind = "'var'"
			} else if def.kind == .class_name {
				kind = 'class'
				lexical = true
			} else if def.kind == .variable && def.parent_kind in ['let', 'const'] {
				kind = "'${def.parent_kind}'"
				lexical = true
			}
			if kind == '' || (lexical && !lexical_bindings) {
				continue
			}
			findings << Finding{
				stmt:       position_of(def.node)
				message_id: if readonly {
					'redeclarationOfReadonlyGlobal'
				} else if lexical {
					'globalLexicalBinding'
				} else {
					'globalNonLexicalBinding'
				}
				data:       if readonly {
					map[string]string{}
				} else {
					{
						'kind': kind
					}
				}
			}
		}
		if readonly && variable.defs.len == 0 {
			for r in variable.references {
				reference := tree.references[r]
				if !reference.write || reference.read {
					continue
				}
				mut node := reference.identifier
				mut assignment := ?C.TSNode(none)
				for {
					node = node_parent(node) or { break }
					if node_kind(node) in ['assignment_expression', 'augmented_assignment_expression',
						'for_in_statement'] {
						assignment = node
						break
					}
				}
				findings << Finding{
					stmt:       position_of(assignment or { reference.identifier })
					message_id: 'assignmentToReadonlyGlobal'
				}
			}
		}
	}
	// Undeclared assigned variables.
	for implicit in tree.implicit {
		for def in implicit.defs {
			findings << Finding{
				stmt:       position_of(def.node)
				message_id: 'globalVariableLeak'
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
