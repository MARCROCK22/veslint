module rules

import estree
import time

// Port of the `unicorn/prefer-import-meta-properties` rule of eslint-plugin-unicorn 79.0.0 (it has
// no options), with its fix.

const upimp_messages = {
	'error/calculate-dirname':  'Do not construct dirname.'
	'error/calculate-filename': 'Do not construct filename using `fileURLToPath()`.'
}

fn (mut c Checker) lint_unicorn_prefer_import_meta_properties(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut ctx := c.un_ctx(root, t, tokens, abs_path)
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .meta_property {
			continue
		}
		stats.checked++
		meta := t.node(node, .meta) or { continue }
		property := t.node(node, .property) or { continue }
		if (t.string_of(meta, .name) or { '' }) != 'import'
			|| (t.string_of(property, .name) or { '' }) != 'meta' {
			continue
		}
		member := t.nodes[node].parent
		if member < 0 || !un_is_member(t, member, UnMember{
			properties: ['url', 'filename']
			computed:   false
			optional:   false
		}) {
			continue
		}
		name := t.string_of(t.node(member, .property) or { continue }, .name) or { continue }
		if name == 'filename' {
			c.upimp_from_filename(mut ctx, member, false, mut findings)
			continue
		}
		parent := t.nodes[member].parent
		// `url.fileURLToPath(import.meta.url)`
		if c.upimp_is_file_url_to_path(mut ctx, parent)
			&& (t.list(parent, .arguments) or { []int{} })[0] == member {
			c.upimp_from_filename(mut ctx, parent, true, mut findings)
			continue
		}
		// `new URL(import.meta.url)`, `new URL('.', import.meta.url)`
		if !un_is_new(t, parent, names: ['URL'], minimum_arguments: 1, maximum_arguments: 2) {
			continue
		}
		new_url := parent
		url_parent := t.nodes[new_url].parent
		arguments := t.list(new_url, .arguments) or { continue }
		if arguments.len == 1 && arguments[0] == member
			&& c.upimp_is_file_url_to_path(mut ctx, url_parent)
			&& (t.list(url_parent, .arguments) or { []int{} })[0] == new_url {
			c.upimp_from_filename(mut ctx, url_parent, true, mut findings)
			continue
		}
		if arguments.len == 2 && (un_static_string_value(t, arguments[0]) or { '' }) in [
			'.',
			'./',
		]
			&& arguments[1] == member && c.upimp_is_file_url_to_path(mut ctx, url_parent)
			&& (t.list(url_parent, .arguments) or { []int{} })[0] == new_url {
			findings << c.upimp_problem(t, tokens, url_parent, 'dirname')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// upimp_problem ports getProblem: the call becomes `import.meta.<name>`, unless a comment is in it.
fn (c &Checker) upimp_problem(t &estree.EsTree, tokens &SourceTokens, node int, name string) Finding {
	has_fix := tokens.comments_inside(t.nodes[node].start, t.nodes[node].end).len == 0
	return Finding{
		stmt:       c.es_tree_position(t, node)
		message_id: if name == 'dirname' {
			'error/calculate-dirname'
		} else {
			'error/calculate-filename'
		}
		has_fix:    has_fix
		fix:        if has_fix {
			fix_replace_range(t.nodes[node].start, t.nodes[node].end, 'import.meta.${name}')
		} else {
			Fix{}
		}
	}
}

// upimp_from_filename ports iterateProblemsFromFilename: a dirname made from the filename.
fn (mut c Checker) upimp_from_filename(mut ctx UnCtx, node int, report_filename bool, mut findings []Finding) {
	t := ctx.t
	parent := t.nodes[node].parent
	if parent < 0 {
		return
	}
	// `path.dirname(filename)`
	if c.upimp_is_path_dirname(mut ctx, parent) && (t.list(parent, .arguments) or { []int{} })[0] == node {
		findings << c.upimp_problem(t, ctx.tokens, parent, 'dirname')
		return
	}
	if report_filename {
		findings << c.upimp_problem(t, ctx.tokens, node, 'filename')
	}
	if t.typ(parent) != .variable_declarator || (t.node(parent, .init) or { -1 }) != node {
		return
	}
	id := t.node(parent, .id) or { return }
	declaration := t.nodes[parent].parent
	if t.typ(id) != .identifier || t.typ(declaration) != .variable_declaration
		|| (t.string_of(declaration, .kind) or { '' }) != 'const' {
		return
	}
	v := c.un_find_variable(ctx, id)
	if v < 0 {
		return
	}
	tree := c.scope_tree(ctx.root)
	for r in tree.variables[v].references {
		reference := tree.references[r]
		if !reference.is_read_only() {
			continue
		}
		identifier := c.es_index_of(t, reference.identifier) or { continue }
		call := t.nodes[identifier].parent
		if c.upimp_is_path_dirname(mut ctx, call)
			&& (t.list(call, .arguments) or { []int{} })[0] == identifier {
			findings << c.upimp_problem(t, ctx.tokens, call, 'dirname')
		}
	}
}

fn (mut c Checker) upimp_is_file_url_to_path(mut ctx UnCtx, node int) bool {
	return c.upimp_is_builtin_call(mut ctx, node, ['url', 'node:url'], 'fileURLToPath')
}

fn (mut c Checker) upimp_is_path_dirname(mut ctx UnCtx, node int) bool {
	return c.upimp_is_builtin_call(mut ctx, node, ['path', 'node:path'], 'dirname')
}

// upimp_is_builtin_call ports isNodeBuiltinModuleFunctionCall: a call of `function` of one of
// `modules`, by a member of the module, a named import or a destructured `const`.
fn (mut c Checker) upimp_is_builtin_call(mut ctx UnCtx, node int, modules []string, function string) bool {
	t := ctx.t
	if node < 0 || !un_is_call(t, node, optional: false, arguments_length: 1) {
		return false
	}
	mut visited := map[int]bool{}
	return c.upimp_is_function_expression(mut ctx, t.node(node, .callee) or { return false },
		true, modules, function, mut visited)
}

// upimp_is_function_expression ports isBuiltinModuleFunctionExpression (`property` is the
// checkKind 'property', else 'module').
fn (mut c Checker) upimp_is_function_expression(mut ctx UnCtx, node int, property bool, modules []string, function string, mut visited map[int]bool) bool {
	t := ctx.t
	match t.typ(node) {
		.member_expression {
			if !(property && un_is_member(t, node, UnMember{
				properties: [function]
				computed:   false
				optional:   false
			})) {
				return false
			}
			return c.upimp_is_function_expression(mut ctx, t.node(node, .object) or { return false },
				false, modules, function, mut visited)
		}
		.call_expression {
			// `process.getBuiltinModule('x')`
			return !property && un_is_method_call(t, node,
				objects:          ['process']
				methods:          ['getBuiltinModule']
				arguments_length: 1
				optional_member:  false
				optional_call:    false
			) && (un_static_string_value(t, (t.list(node, .arguments) or { return false })[0]) or {
				''
			}) in modules
		}
		.identifier {
			if node in visited {
				return false
			}
			visited[node] = true
			v := c.un_find_variable(ctx, node)
			if v < 0 {
				return false
			}
			tree := c.scope_tree(ctx.root)
			if tree.variables[v].defs.len != 1 {
				return false
			}
			def := tree.variables[v].defs[0]
			mut name := c.es_index_of(t, def.name) or { return false }
			// The name of a shorthand property of a pattern is its value (the key has the same
			// range).
			holder := t.nodes[name].parent
			if holder >= 0 && t.typ(holder) == .property && (t.node(holder, .key) or { -1 }) == name {
				name = t.node(holder, .value) or { name }
			}
			if def.kind == .import_binding {
				specifier := t.nodes[name].parent
				declaration := t.nodes[specifier].parent
				source := t.node(declaration, .source) or { return false }
				if (un_static_string_value(t, source) or { '' }) !in modules {
					return false
				}
				if !property {
					return t.typ(specifier) in [.import_default_specifier, .import_namespace_specifier]
				}
				imported := t.node(specifier, .imported) or { return false }
				return t.typ(specifier) == .import_specifier
					&& (t.string_of(imported, .name) or { '' }) == function
			}
			return def.kind == .variable
				&& c.upimp_is_function_pattern(mut ctx, name, property, modules, function, mut visited)
		}
		else {
			return false
		}
	}
}

// upimp_is_function_pattern ports isBuiltinModuleFunctionPattern.
fn (mut c Checker) upimp_is_function_pattern(mut ctx UnCtx, node int, property bool, modules []string, function string, mut visited map[int]bool) bool {
	t := ctx.t
	parent := t.nodes[node].parent
	if parent < 0 {
		return false
	}
	if t.typ(parent) == .variable_declarator {
		init := t.node(parent, .init) or { return false }
		declaration := t.nodes[parent].parent
		if (t.node(parent, .id) or { -1 }) != node || t.typ(declaration) != .variable_declaration
			|| (t.string_of(declaration, .kind) or { '' }) != 'const' {
			return false
		}
		return c.upimp_is_function_expression(mut ctx, init, property, modules, function, mut
			visited)
	}
	if t.typ(parent) == .property {
		key := t.node(parent, .key) or { return false }
		if !(property && (t.node(parent, .value) or { -1 }) == node
			&& !(t.flag(parent, .computed) or { false }) && t.typ(key) == .identifier
			&& (t.string_of(key, .name) or { '' }) == function) {
			return false
		}
		// The object pattern.
		return c.upimp_is_function_pattern(mut ctx, t.nodes[parent].parent, false, modules,
			function, mut visited)
	}
	return false
}
