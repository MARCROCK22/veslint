module rules

import json2
import os
import time
import treesitter { named_children, node_field, node_kind }

// Port of the `vue/no-restricted-call-after-await` rule of eslint-plugin-vue 10.12.1 (options:
// `{module, path, message}` objects): a call of a restricted export of a module in a `setup`
// function after an `await` of that function. A relative or absolute `module` names a file,
// matched against the relative imports of the file (path.join, require.resolve of a directory).

const vue_no_restricted_call_after_await_messages = {
	'restricted': '{{message}}'
}

struct VnrcaOption {
	module   string
	paths    []string
	has_path bool // `path` is a list (maybe empty): no `default`
	message  string
}

fn vue_no_restricted_call_after_await_options(options []json2.Any) ![]VnrcaOption {
	mut out := []VnrcaOption{}
	for option in options {
		if option !is map[string]json2.Any {
			return error('an option of `${vue_no_restricted_call_after_await}` must be an object')
		}
		o := option as map[string]json2.Any
		for key, _ in o {
			if key !in ['module', 'path', 'message'] {
				return error('unknown property `${key}` in an option of `${vue_no_restricted_call_after_await}`')
			}
		}
		module := o['module'] or {
			return error('an option of `${vue_no_restricted_call_after_await}` must have `module`')
		}
		if module !is string {
			return error('`module` of `${vue_no_restricted_call_after_await}` must be a string')
		}
		mut paths := []string{}
		mut has_path := false
		if p := o['path'] {
			if p is string {
				paths << p
				has_path = p != ''
			} else if p is []json2.Any {
				has_path = true
				for item in p {
					if item !is string {
						return error('`path` of `${vue_no_restricted_call_after_await}` must be strings')
					}
					paths << item as string
				}
			} else {
				return error('`path` of `${vue_no_restricted_call_after_await}` must be a string or a list')
			}
		}
		mut message := ''
		if m := o['message'] {
			if m !is string || (m as string) == '' {
				return error('`message` of `${vue_no_restricted_call_after_await}` must be a non-empty string')
			}
			message = m as string
		}
		out << VnrcaOption{
			module:   module as string
			paths:    paths
			has_path: has_path
			message:  message
		}
	}
	return out
}

fn (mut c Checker) lint_vue_no_restricted_call_after_await(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	options := vue_no_restricted_call_after_await_options(c.rule_options(vue_no_restricted_call_after_await))!
	mut findings := []Finding{}
	if options.len == 0 {
		return findings
	}
	s := c.vue_script(root, abs_path) or { return findings }
	if s.objects.len == 0 {
		return findings
	}
	t := c.es_tree(root, abs_path) or { return findings }
	scopes := vaa_scopes(t)
	calls := c.vaa_setup_calls_after_await(t, s, &scopes)
	if calls.len == 0 {
		return findings
	}
	// Program: the restricted calls (a later option's message wins, as a Map's set).
	mut restricted := map[int]string{}
	mut local_imports := map[string][]string{}
	mut local_built := false
	for option in options {
		mut modules := []string{}
		if option.module.starts_with('.') || os.is_abs_path(option.module) {
			module_path := vnrca_safe_require_resolve(if option.module.starts_with('.') {
				os.norm_path(os.join_path(os.getwd(), option.module))
			} else {
				os.norm_path(option.module)
			})
			if !local_built {
				local_imports = c.vnrca_local_imports(root, s.filename)
				local_built = true
			}
			modules = local_imports[module_path] or { []string{} }
		} else {
			modules = [option.module]
		}
		paths := if option.has_path { option.paths } else { ['default'] }
		for module in modules {
			mut trace := EsTrace{
				call: true
			}
			for i := paths.len - 1; i >= 0; i-- {
				trace = EsTrace{
					children: {
						paths[i]: trace
					}
				}
			}
			trace = EsTrace{
				...trace
				esm: true
			}
			message := if option.message != '' {
				option.message
			} else {
				mut parts := ['import("${module}")']
				parts << paths
				'`${parts.join('.')}` is forbidden after an `await` expression.'
			}
			for r in c.es_esm_references(root, {
				module: trace
			})
			{
				if r.kind != 'call' {
					continue
				}
				call := c.es_index_of(t, r.node) or { continue }
				restricted[call] = message
			}
		}
	}
	for call in calls {
		stats.checked++
		message := restricted[call] or { continue }
		findings << Finding{
			stmt:       c.es_tree_position(t, call)
			message_id: 'restricted'
			data:       {
				'message': message
			}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vnrca_local_imports is getAllLocalImports: the relative sources of the import declarations, by
// the path they resolve to from the file's directory.
fn (mut c Checker) vnrca_local_imports(root C.TSNode, filename string) map[string][]string {
	mut out := map[string][]string{}
	dir := os.dir(filename)
	for statement in named_children(root) {
		if node_kind(statement) != 'import_statement' {
			continue
		}
		source_node := node_field(statement, 'source') or { continue }
		source := c.string_if_constant_unscoped(source_node) or { continue }
		if !source.starts_with('.') {
			continue
		}
		module_path := vnrca_safe_require_resolve(os.norm_path(os.join_path(dir, source)))
		out[module_path] << source
	}
	return out
}

// vnrca_safe_require_resolve is safeRequireResolve: require.resolve of a directory (its
// package.json's `main`, else its index file), the path itself otherwise.
fn vnrca_safe_require_resolve(id string) string {
	if !os.is_dir(id) {
		return id
	}
	extensions := ['', '.js', '.json', '.node']
	package_json := os.join_path(id, 'package.json')
	if text := os.read_file(package_json) {
		if decoded := json2.decode[json2.Any](text) {
			if decoded is map[string]json2.Any {
				if main := decoded['main'] {
					if main is string && main != '' {
						base := os.norm_path(os.join_path(id, main))
						for ext in extensions {
							if os.is_file(base + ext) {
								return base + ext
							}
						}
						for ext in extensions[1..] {
							if os.is_file(os.join_path(base, 'index' + ext)) {
								return os.join_path(base, 'index' + ext)
							}
						}
					}
				}
			}
		}
	}
	for ext in extensions[1..] {
		if os.is_file(os.join_path(id, 'index' + ext)) {
			return os.join_path(id, 'index' + ext)
		}
	}
	return id
}
