module rules

import crypto.sha1
import json2
import os
import tsgo { CompilerOptions }
import treesitter { node_start, root_node, token_ends }

// The scope tree of each program of tests/scope/ must be what ESLint's scope manager holds for
// it: tests/scope_cases.json comes from tools/gen_scope_cases.mjs, which runs the real
// @typescript-eslint/parser and scope-manager inside ESLint's Linter with the languageOptions,
// linterOptions and compilerOptions of the case, and writes every scope, variable and reference.
// The test gives the same options to the code a lint run uses (inline_config, file_scope_setup
// and scope_tree) and compares everything: the scopes (type, range, upper and variable scope,
// isStrict and the references left to the upper scope), their variables in order (definitions,
// identifiers and references in resolution order), their references in order (identifier,
// read/write/init flags, type/value kind, variable resolved to; of an identifier, its name and
// where it starts: ESTree's range includes a type annotation), the unresolved references, the
// implicit global variables and, through a digest, every variable of the global scope with what
// ESLint sets on it.

const scope_oracle_types = {
	ScopeKind.global:                   'global'
	ScopeKind.esmodule:                 'module'
	ScopeKind.function:                 'function'
	ScopeKind.function_expression_name: 'function-expression-name'
	ScopeKind.block:                    'block'
	ScopeKind.catch_clause:             'catch'
	ScopeKind.for_statement:            'for'
	ScopeKind.switch_statement:         'switch'
	ScopeKind.with_statement:           'with'
	ScopeKind.class_scope:              'class'
	ScopeKind.class_field_initializer:  'class-field-initializer'
	ScopeKind.class_static_block:       'class-static-block'
	ScopeKind.ts_enum:                  'tsEnum'
	ScopeKind.ts_module:                'tsModule'
	ScopeKind.type_scope:               'type'
	ScopeKind.function_type:            'functionType'
	ScopeKind.conditional_type:         'conditionalType'
	ScopeKind.mapped_type:              'mappedType'
}

const scope_oracle_definitions = {
	DefKind.catch_clause:    'CatchClause'
	DefKind.class_name:      'ClassName'
	DefKind.function_name:   'FunctionName'
	DefKind.import_binding:  'ImportBinding'
	DefKind.parameter:       'Parameter'
	DefKind.ts_enum_member:  'TSEnumMemberName'
	DefKind.ts_enum_name:    'TSEnumName'
	DefKind.ts_module_name:  'TSModuleName'
	DefKind.type_definition: 'Type'
	DefKind.variable:        'Variable'
}

fn scope_oracle_field(entry map[string]json2.Any, name string) json2.Any {
	return entry[name] or { panic('no ${name}') }
}

fn scope_oracle_int(entry map[string]json2.Any, name string) int {
	return scope_oracle_field(entry, name).int()
}

// scope_oracle_tree builds the scope tree of a case the way a lint run does.
fn scope_oracle_tree(item map[string]json2.Any) (&ScopeTree, string) {
	file := scope_oracle_field(item, 'file').str()
	src := scope_oracle_field(item, 'source').str()
	parser := if file.ends_with('.tsx') {
		treesitter.new_tsx_parser() or { panic(err) }
	} else {
		treesitter.new_parser() or { panic(err) }
	}
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	// The compiler options as TypeScript holds them (what tsgo answers): null without a program,
	// where typescript-eslint's parser has no lib of its own and analyze() takes `esnext`.
	compiler := scope_oracle_field(item, 'compilerOptions')
	project := if compiler is map[string]json2.Any {
		new_scope_project(json2.decode[CompilerOptions](compiler.json_str()) or { panic(err) })
	} else {
		ScopeProject{
			libs: ['esnext']
		}
	}
	linter := scope_oracle_field(item, 'linterOptions').as_map()
	config := LintConfig{
		language:         parse_language_options(scope_oracle_field(item, 'languageOptions'))
		no_inline_config: (linter['noInlineConfig'] or { json2.Any(false) }).bool()
	}
	mut c := &Checker{
		src:           src
		tokens:        token_ends(root)
		node_index:    treesitter.new_node_index(root)
		scope_project: project
	}
	inline := c.inline_config(root, config)
	c.scope_setup = c.file_scope_setup(config, inline)
	return c.scope_tree(root), src
}

// scope_oracle_compare lists the differences between the scope tree of a case and ESLint's.
fn scope_oracle_compare(item map[string]json2.Any) []string {
	t, src := scope_oracle_tree(item)
	mut out := []string{}
	expected := scope_oracle_field(item, 'scopes').as_array()
	if expected.len != t.scopes.len {
		got_types := t.scopes.map(scope_oracle_types[it.kind])
		want_types := expected.map(scope_oracle_field(it.as_map(), 'type').str())
		out << 'scopes: ${got_types}, ESLint has ${want_types}'
		return out
	}
	// The id of a reference is its place in the references of the scopes, in order.
	mut ids := map[int]int{}
	mut positions := map[int]int{} // the place of a variable in its scope
	for scope in t.scopes {
		for r in scope.references {
			ids[r] = ids.len
		}
		for i, v in scope.variables {
			positions[v] = i
		}
	}
	line := fn [src] (offset int) int {
		return src[..offset].count('\n') + 1
	}
	for s, scope in t.scopes {
		want := expected[s].as_map()
		want_type := scope_oracle_field(want, 'type').str()
		want_start := scope_oracle_int(want, 'start')
		label := 'scope ${s} (${want_type} ${scope_oracle_field(want, 'block').str()} at line ${line(want_start)})'
		got_head := '${scope_oracle_types[scope.kind]} [${scope.start},${scope.end}) upper ${scope.upper} variableScope ${scope.variable_scope} strict ${t.is_strict(s)} through ${scope.through.map(ids[it])}'
		want_through := scope_oracle_field(want, 'through').as_array().map(it.int())
		want_head := '${want_type} [${want_start},${scope_oracle_int(want, 'end')}) upper ${scope_oracle_int(want, 'upper')} variableScope ${scope_oracle_int(want, 'variableScope')} strict ${scope_oracle_field(want, 'isStrict').bool()} through ${want_through}'
		if got_head != want_head {
			out << '${label}: ${got_head}, ESLint has ${want_head}'
		}
		// Variables: of the global scope, only the ones ESLint declared or something references.
		mut got_variables := []string{}
		for i, v in scope.variables {
			variable := t.variables[v]
			if s == 0 && variable.lib && variable.references.len == 0 {
				continue
			}
			mut defs := []string{}
			for def in variable.defs {
				defs << '${scope_oracle_definitions[def.kind]}@${node_start(def.name)}'
			}
			identifiers := variable.identifiers.map(node_start(it))
			resolved := variable.references.map(ids[it])
			got_variables << '${variable.name}#${i} defs[${defs.join(' ')}] identifiers${identifiers} references${resolved}'
		}
		mut want_variables := []string{}
		for entry in scope_oracle_field(want, 'variables').as_array() {
			variable := entry.as_map()
			mut defs := []string{}
			for def in scope_oracle_field(variable, 'defs').as_array() {
				d := def.as_map()
				kind := scope_oracle_field(d, 'type').str()
				defs << '${kind}@${scope_oracle_int(d, 'start')}'
			}
			name := scope_oracle_field(variable, 'name').str()
			identifiers := scope_oracle_field(variable, 'identifiers').as_array().map(it.int())
			resolved := scope_oracle_field(variable, 'references').as_array().map(it.int())
			want_variables << '${name}#${scope_oracle_int(variable, 'index')} defs[${defs.join(' ')}] identifiers${identifiers} references${resolved}'
		}
		scope_oracle_diff(mut out, '${label} variables', got_variables, want_variables)
		mut got_references := []string{}
		for r in scope.references {
			ref := t.references[r]
			flags := (if ref.read { 'R' } else { '' }) + (if ref.write { 'W' } else { '' }) +
				(if ref.init { 'i' } else { '' })
			kind := (if ref.type_ref { 'T' } else { '' }) + (if ref.value_ref { 'V' } else { '' })
			resolved := if ref.resolved >= 0 {
				'${t.variables[ref.resolved].scope}.${positions[ref.resolved]}'
			} else {
				'-'
			}
			start := node_start(ref.identifier)
			got_references << '#${ids[r]} ${ref.name}@${start} line ${line(start)} ${flags} ${kind} -> ${resolved}'
		}
		mut want_references := []string{}
		for entry in scope_oracle_field(want, 'references').as_array() {
			ref := entry.as_map()
			target := scope_oracle_field(ref, 'resolved').as_array().map(it.int().str())
			resolved := if target.len == 0 { '-' } else { target.join('.') }
			name := scope_oracle_field(ref, 'name').str()
			start := scope_oracle_int(ref, 'start')
			flags := scope_oracle_field(ref, 'flags').str()
			kind := scope_oracle_field(ref, 'kind').str()
			want_references << '#${scope_oracle_int(ref, 'id')} ${name}@${start} line ${line(start)} ${flags} ${kind} -> ${resolved}'
		}
		scope_oracle_diff(mut out, '${label} references', got_references, want_references)
	}
	global := scope_oracle_field(item, 'global').as_map()
	through := t.through.map(ids[it])
	want_through := scope_oracle_field(global, 'through').as_array().map(it.int())
	if through != want_through {
		out << 'through: ${through}, ESLint has ${want_through}'
	}
	implicit := t.implicit.map('${it.name}${it.defs.map('[${node_start(it.name)}, ${node_start(it.node)}]')}')
	want_implicit := scope_oracle_field(global, 'implicit').as_array().map(fn (entry json2.Any) string {
		variable := entry.as_map()
		defs := scope_oracle_field(variable, 'defs').as_array().map(fn (def json2.Any) string {
			pair := def.as_array()
			return '[${pair[0].int()}, ${pair[1].int()}]'
		})
		return '${scope_oracle_field(variable, 'name').str()}${defs}'
	})
	if implicit != want_implicit {
		out << 'implicit: ${implicit}, ESLint has ${want_implicit}'
	}
	lines := scope_oracle_global_lines(t)
	digest := sha1.hexhash(lines.join('\n'))
	if digest != scope_oracle_field(global, 'digest').str() {
		count := scope_oracle_int(global, 'count')
		out << 'the ${lines.len} variables of the global scope differ from the ${count} of ESLint (compare `node tools/gen_scope_cases.mjs --globals <case>` with the output of VESLINT_SCOPE_GLOBALS=<case>)'
	}
	return out
}

// scope_oracle_global_lines are the lines of the digest: one per variable of the global scope.
fn scope_oracle_global_lines(t &ScopeTree) []string {
	mut lines := []string{}
	for v in t.scopes[0].variables {
		variable := t.variables[v]
		lines << [
			variable.name,
			if variable.lib { 'lib' } else { 'variable' },
			(if variable.is_type_variable() { 'T' } else { '' }) +
				(if variable.is_value_variable() { 'V' } else { '' }),
			if variable.writeable { 'writable' } else { '' },
			if variable.eslint_explicit_global { 'explicit' } else { '' },
			variable.eslint_implicit_global_setting,
			if variable.eslint_used { 'used' } else { '' },
			variable.references.len.str(),
		].join('\t')
	}
	return lines
}

// scope_oracle_diff reports the first entries two lists differ in.
fn scope_oracle_diff(mut out []string, label string, got []string, want []string) {
	if got == want {
		return
	}
	mut shown := 0
	for i in 0 .. if got.len > want.len { got.len } else { want.len } {
		g := got[i] or { '(nothing)' }
		w := want[i] or { '(nothing)' }
		if g != w {
			out << '${label}[${i}]: ${g}, ESLint has ${w}'
			shown++
			if shown == 4 {
				out << '${label}: … (${got.len} entries, ESLint has ${want.len})'
				break
			}
		}
	}
}

fn test_scopes_match_eslint() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'scope_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	cases := scope_oracle_field(data, 'cases').as_array()
	assert cases.len >= 45
	only := os.getenv('VESLINT_SCOPE_CASE')
	listed := os.getenv('VESLINT_SCOPE_GLOBALS')
	mut failures := []string{}
	mut references := 0
	for entry in cases {
		item := entry.as_map()
		name := scope_oracle_field(item, 'name').str()
		if only != '' && name != only {
			continue
		}
		if listed == name {
			t, _ := scope_oracle_tree(item)
			println(scope_oracle_global_lines(t).join('\n'))
		}
		for scope in scope_oracle_field(item, 'scopes').as_array() {
			references += scope_oracle_field(scope.as_map(), 'references').as_array().len
		}
		for difference in scope_oracle_compare(item) {
			failures << '${name}: ${difference}'
		}
	}
	if failures.len > 0 {
		eprintln(failures.join('\n'))
	}
	assert failures.len == 0, '${failures.len} differences with ESLint'
	assert only != '' || references >= 1500
}
