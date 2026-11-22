module rules

import treesitter { has_child_kind, named_children, node_field, node_kind }

// ReferenceTracker#iterateEsmReferences and #iterateCjsReferences of @eslint-community/eslint-utils
// (mode "strict", the default), on the trace maps and the variable and property tracing of
// eslint_utils.v (es_global_references). Their nodes are tree-sitter nodes (es_index_of gives
// the ESTree ones).

// es_esm_references ports iterateEsmReferences: the reads, calls and constructions of the paths
// of the trace map from the modules the file imports (or re-exports). A module whose trace has
// `esm` is an ES module (its named exports are the keys); for the others, the default export is
// the module (CommonJS interop: `import x from 'm'; x.a()` is the path [m, a]).
fn (mut c Checker) es_esm_references(root C.vt_node, trace map[string]EsTrace) []EsTraced {
	mut out := []EsTraced{}
	for statement in named_children(root) {
		kind := node_kind(statement)
		if kind !in ['import_statement', 'export_statement'] {
			continue
		}
		source := node_field(statement, 'source') or { continue }
		module_id := c.string_if_constant_unscoped(source) or { continue }
		next := trace[module_id] or { continue }
		path := [module_id]
		if next.read {
			out << EsTraced{
				node: statement
				path: path
				kind: 'read'
			}
		}
		if kind == 'export_statement' && !has_child_kind(statement, 'export_clause') {
			// ExportAllDeclaration
			for key, export_trace in next.children {
				if export_trace.read {
					out << EsTraced{
						node: statement
						path: [module_id, key]
						kind: 'read'
					}
				}
			}
			continue
		}
		specifier_trace := if next.esm {
			next
		} else {
			EsTrace{
				children: {
					'default': next
				}
			}
		}
		mut found := []EsTraced{}
		for specifier in es_esm_specifiers(statement) {
			c.es_import_references(root, specifier, path, specifier_trace, mut found)
		}
		if next.esm {
			out << found
			continue
		}
		for report in found {
			// exceptDefault: the `default` right after the module is the module itself.
			mut filtered := []string{}
			for i, name in report.path {
				if !(i == 1 && name == 'default') {
					filtered << name
				}
			}
			if filtered.len >= 2 || report.kind != 'read' {
				out << EsTraced{
					node: report.node
					path: filtered
					kind: report.kind
				}
			}
		}
	}
	return out
}

// es_esm_specifiers are the specifiers of an import or export statement: the identifier of a
// default import, the namespace_import, the import_specifier and export_specifier nodes.
fn es_esm_specifiers(statement C.vt_node) []C.vt_node {
	mut out := []C.vt_node{}
	for part in named_children(statement) {
		match node_kind(part) {
			'import_clause' {
				for clause in named_children(part) {
					match node_kind(clause) {
						'identifier', 'namespace_import' {
							out << clause
						}
						'named_imports' {
							for specifier in named_children(clause) {
								if node_kind(specifier) == 'import_specifier' {
									out << specifier
								}
							}
						}
						else {}
					}
				}
			}
			'export_clause' {
				for specifier in named_children(part) {
					if node_kind(specifier) == 'export_specifier' {
						out << specifier
					}
				}
			}
			else {}
		}
	}
	return out
}

// es_import_references ports _iterateImportReferences.
fn (mut c Checker) es_import_references(root C.vt_node, specifier C.vt_node, path []string, trace EsTrace, mut out []EsTraced) {
	tree := c.scope_tree(root)
	mut stack := []int{}
	match node_kind(specifier) {
		'identifier', 'import_specifier' {
			mut key := 'default'
			mut local := specifier
			if node_kind(specifier) == 'import_specifier' {
				imported := node_field(specifier, 'name') or { return }
				key = if node_kind(imported) == 'string' {
					c.string_if_constant_unscoped(imported) or { return }
				} else {
					c.text(imported)
				}
				local = node_field(specifier, 'alias') or { imported }
			}
			next := trace.children[key] or { return }
			mut next_path := path.clone()
			next_path << key
			if next.read {
				out << EsTraced{
					node: specifier
					path: next_path
					kind: 'read'
				}
			}
			v := tree.declared_variable(local)
			if v >= 0 {
				c.es_trace_variable(root, v, next_path, next, false, mut stack, mut out)
			}
		}
		'namespace_import' {
			local := first_named(specifier) or { return }
			v := tree.declared_variable(local)
			if v >= 0 {
				c.es_trace_variable(root, v, path, trace, false, mut stack, mut out)
			}
		}
		'export_specifier' {
			local := node_field(specifier, 'name') or { return }
			key := if node_kind(local) == 'string' {
				c.string_if_constant_unscoped(local) or { return }
			} else {
				c.text(local)
			}
			next := trace.children[key] or { return }
			if next.read {
				mut next_path := path.clone()
				next_path << key
				out << EsTraced{
					node: specifier
					path: next_path
					kind: 'read'
				}
			}
		}
		else {}
	}
}

// es_cjs_references ports iterateCjsReferences: the paths of the trace map from the modules the
// global `require` loads (when it is a global the file does not modify).
fn (mut c Checker) es_cjs_references(root C.vt_node, trace map[string]EsTrace) []EsTraced {
	mut out := []EsTraced{}
	requires := c.es_global_references(root, {
		'require': EsTrace{
			call: true
		}
	})
	mut stack := []int{}
	for r in requires {
		args := node_field(r.node, 'arguments') or { continue }
		first := first_named(args) or { continue }
		key := c.string_if_constant_unscoped(first) or { continue }
		next := trace[key] or { continue }
		path := [key]
		if next.read {
			out << EsTraced{
				node: r.node
				path: path
				kind: 'read'
			}
		}
		c.es_trace_properties(root, r.node, path, next, mut stack, mut out)
	}
	return out
}
