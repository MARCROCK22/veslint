module rules

import json2
import jsregexp
import time
import treesitter { children, named_children, node_field, node_kind, position_of }

// Port of the `no-restricted-exports` rule of ESLint 10.6.0.

const nre_messages = {
	'restrictedNamed':   "'{{name}}' is restricted from being used as an exported name."
	'restrictedDefault': "Exporting 'default' is restricted."
}

struct NreOptions {
	names          []string
	pattern        ?jsregexp.RegexpProgram
	direct         bool
	named          bool
	default_from   bool
	named_from     bool
	namespace_from bool
	has_defaults   bool // restrictDefaultExports is given
}

fn nre_options(options []json2.Any) !NreOptions {
	o := option_object(no_restricted_exports, options, ['restrictedNamedExports',
		'restrictedNamedExportsPattern', 'restrictDefaultExports'])!
	mut pattern := ?jsregexp.RegexpProgram(none)
	if value := o.values['restrictedNamedExportsPattern'] {
		pattern = jsregexp.regexp_compile(value.str()) or {
			return error('restrictedNamedExportsPattern of `${no_restricted_exports}` is not a valid regular expression')
		}
	}
	mut defaults := map[string]json2.Any{}
	mut has_defaults := false
	if value := o.values['restrictDefaultExports'] {
		if value is map[string]json2.Any {
			defaults = value.as_map()
			has_defaults = true
		}
	}
	flag := fn [defaults] (key string) bool {
		value := defaults[key] or { return false }
		return value is bool && value as bool
	}
	return NreOptions{
		names:          o.string_list('restrictedNamedExports')!
		pattern:        pattern
		direct:         flag('direct')
		named:          flag('named')
		default_from:   flag('defaultFrom')
		named_from:     flag('namedFrom')
		namespace_from: flag('namespaceFrom')
		has_defaults:   has_defaults
	}
}

fn (mut c Checker) lint_no_restricted_exports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	o := nre_options(c.rule_options(no_restricted_exports))!
	mut findings := []Finding{}
	for node in c.nodes_of_kinds(root, ['export_statement'], []) {
		stats.checked++
		parts := children(node)
		if parts.any(node_kind(it) == 'default') {
			// ExportDefaultDeclaration
			if o.direct {
				findings << Finding{
					stmt:       position_of(node)
					message_id: 'restrictedDefault'
				}
			}
			continue
		}
		source := node_field(node, 'source')
		if namespace := parts.filter(node_kind(it) == 'namespace_export')[0] {
			// `export * as name from 'mod'`
			exported := named_children(namespace).filter(node_kind(it) != 'comment').last()
			c.nre_check(exported, .namespace, false, '', o, mut findings)
			continue
		}
		if clause := parts.filter(node_kind(it) == 'export_clause')[0] {
			for specifier in named_children(clause) {
				if node_kind(specifier) != 'export_specifier' {
					continue
				}
				local := node_field(specifier, 'name') or { continue }
				exported := node_field(specifier, 'alias') or { local }
				c.nre_check(exported, .specifier, source != none, c.nre_name(local), o, mut
					findings)
			}
			continue
		}
		mut declaration := node_field(node, 'declaration') or { continue }
		if node_kind(declaration) == 'ambient_declaration' {
			declaration = named_children(declaration).filter(node_kind(it) != 'comment')[0] or {
				continue
			}
		}
		match node_kind(declaration) {
			'function_declaration', 'generator_function_declaration', 'class_declaration',
			'abstract_class_declaration' {
				name := node_field(declaration, 'name') or { continue }
				c.nre_check(name, .declaration, false, '', o, mut findings)
			}
			'variable_declaration', 'lexical_declaration' {
				tree := c.scope_tree(root)
				for v in c.es_declared_variables(root, declaration) {
					for def in tree.variables[v].defs {
						parent := es_def_parent(def) or { continue }
						if node_key(parent) == node_key(declaration) {
							c.nre_check(def.name, .declaration, false, '', o, mut findings)
							break
						}
					}
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

enum NreExport {
	declaration // the id of a declaration
	specifier   // an export specifier
	namespace   // `export * as name`
}

// nre_name ports getModuleExportName: the name of an identifier or the value of a string.
fn (c &Checker) nre_name(n C.TSNode) string {
	if node_kind(n) == 'string' {
		return c.literal_string_value(n) or { c.text(n) }
	}
	return c.identifier_name(n)
}

// nre_check ports checkExportedName.
fn (c &Checker) nre_check(node C.TSNode, kind NreExport, has_source bool, local_name string, o NreOptions, mut findings []Finding) {
	name := c.nre_name(node)
	mut matches_pattern := false
	if program := o.pattern {
		if name != 'default' {
			matches_pattern = jsregexp.regexp_test(program, name) or { false }
		}
	}
	if matches_pattern || name in o.names {
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'restrictedNamed'
			data:       {
				'name': name
			}
		}
		return
	}
	if name != 'default' {
		return
	}
	restricted := match kind {
		.namespace {
			o.namespace_from
		}
		.declaration, .specifier {
			if !has_source {
				o.named
			} else {
				o.has_defaults && ((local_name == 'default' && o.default_from)
					|| (local_name != 'default' && o.named_from))
			}
		}
	}
	if restricted {
		findings << Finding{
			stmt:       position_of(node)
			message_id: 'restrictedDefault'
		}
	}
}
