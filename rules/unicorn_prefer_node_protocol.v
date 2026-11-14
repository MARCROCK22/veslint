module rules

import time

// Port of the `unicorn/prefer-node-protocol` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const upnpr_messages = {
	'prefer-node-protocol': 'Prefer `node:{{moduleName}}` over `{{moduleName}}`.'
}

// upnpr_builtin_modules is the list of builtin-modules 5.3.0 (builtin-modules.json), which
// is-builtin-module 5.0.0 checks names against.
const upnpr_builtin_modules = ['node:assert', 'assert', 'node:assert/strict', 'assert/strict',
	'node:async_hooks', 'async_hooks', 'node:buffer', 'buffer', 'node:child_process', 'child_process',
	'node:cluster', 'cluster', 'node:console', 'console', 'node:constants', 'constants', 'node:crypto',
	'crypto', 'node:dgram', 'dgram', 'node:diagnostics_channel', 'diagnostics_channel', 'node:dns',
	'dns', 'node:dns/promises', 'dns/promises', 'node:domain', 'domain', 'node:events', 'events',
	'node:ffi', 'node:fs', 'fs', 'node:fs/promises', 'fs/promises', 'node:http', 'http', 'node:http2',
	'http2', 'node:https', 'https', 'node:inspector', 'inspector', 'node:inspector/promises',
	'inspector/promises', 'node:module', 'module', 'node:net', 'net', 'node:os', 'os', 'node:path',
	'path', 'node:path/posix', 'path/posix', 'node:path/win32', 'path/win32', 'node:perf_hooks',
	'perf_hooks', 'node:process', 'process', 'node:querystring', 'querystring', 'node:quic',
	'node:readline', 'readline', 'node:readline/promises', 'readline/promises', 'node:repl', 'repl',
	'node:sea', 'node:sqlite', 'node:stream', 'stream', 'node:stream/consumers', 'stream/consumers',
	'node:stream/iter', 'stream/iter', 'node:stream/promises', 'stream/promises', 'node:stream/web',
	'stream/web', 'node:string_decoder', 'string_decoder', 'node:test', 'node:test/reporters',
	'node:timers', 'timers', 'node:timers/promises', 'timers/promises', 'node:tls', 'tls',
	'node:trace_events', 'trace_events', 'node:tty', 'tty', 'node:url', 'url', 'node:util', 'util',
	'node:util/types', 'util/types', 'node:v8', 'v8', 'node:vfs', 'node:vm', 'vm', 'node:wasi',
	'wasi', 'node:worker_threads', 'worker_threads', 'node:zlib', 'zlib', 'node:zlib/iter', 'zlib/iter']

fn (mut c Checker) lint_unicorn_prefer_node_protocol(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	for node in 0 .. t.nodes.len {
		if t.typ(node) !in [.literal, .template_literal] {
			continue
		}
		parent := t.nodes[node].parent
		if parent < 0 {
			continue
		}
		stats.checked++
		is_source := t.typ(parent) in [.import_declaration, .export_named_declaration,
			.export_all_declaration, .import_expression, .ts_import_type]
			&& (t.node(parent, .source) or { -1 }) == node
		is_argument := (un_is_method_call(t, parent,
			objects:          ['process']
			methods:          ['getBuiltinModule']
			arguments_length: 1
			optional_call:    false
			optional_member:  false
		) || un_is_call(t, parent, names: ['require'], arguments_length: 1, optional: false))
			&& (t.list(parent, .arguments) or { []int{} })[0] == node
		if !is_source && !is_argument {
			continue
		}
		value := un_static_string_value(t, node) or { continue }
		if value.starts_with('node:') || value !in upnpr_builtin_modules
			|| 'node:${value}' !in upnpr_builtin_modules {
			continue
		}
		// After the quote.
		position := t.nodes[node].start + 1
		findings << Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'prefer-node-protocol'
			data:       {
				'moduleName': value
			}
			has_fix:    true
			fix:        fix_insert_at(position, 'node:')
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}
