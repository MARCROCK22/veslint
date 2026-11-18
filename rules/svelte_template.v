module rules

import json2
import os
import svelte

// The document side of the svelte/* rules: what eslint-plugin-svelte 3.24.1's rules get from
// ESLint's traversal of svelte-eslint-parser 1.10.1's AST and from src/utils, on the
// svelte.Document of the .svelte file being linted (c.svelte.doc, set by set_svelte). Every
// position is a byte offset of the file (the Svelte nodes', and those of doc.es, the ESTree of the
// script and of the template expressions); the line and column ESLint prints come from the
// document (doc.loc), as for the other rules of a .svelte file.
//
// How a svelte/* rule works:
//   - it returns [] at once unless c.is_svelte(): a project without .svelte files does no work
//     (a rule that also runs on `.svelte.ts` modules or other files tests its own condition);
//   - it walks the nodes it listens to with c.sv_snodes() (the Svelte nodes in the order ESLint
//     enters them) or c.sv_steps() (enter and leave events of the whole Program, ESTree included,
//     in ESLint's order with svelte-eslint-parser's visitor keys), and reads them with
//     c.svelte.doc.nodes[i] (svelte.SNode), the ESTree nodes with c.svelte.doc.es and the helpers
//     of svelte_ast.v (attributes, directives, names, elements, scopes);
//   - it reads the tokens with the sv_token* functions (svelte_tokens.v: doc.tokens and
//     doc.comments, svelte-eslint-parser's tokens of the whole file);
//   - it reports with c.sv_report(start, end, message_id, data), c.sv_report_snode(i, …) or
//     c.sv_report_es(i, …) (a node's `loc`), with Fix values in file bytes;
//   - lint_file does not move its findings (svelte_move_findings keeps the svelte/* ones, which
//     are file offsets already).

// SvelteStep is one event of ESLint's traversal of a .svelte file's AST: entering or leaving a
// node (a Svelte node of doc.nodes or an ESTree node of doc.es).
pub struct SvelteStep {
pub:
	node  svelte.Ref
	leave bool
}

fn sv_snode_ref(i int) svelte.Ref {
	return svelte.Ref{
		es:  false
		idx: i
	}
}

fn sv_es_ref(i int) svelte.Ref {
	return svelte.Ref{
		es:  true
		idx: i
	}
}

// sv_steps are the events of ESLint's traversal of the Program (depth first; the children of a
// Svelte node by svelte-eslint-parser's KEYS, those of an ESTree node by typescript-eslint's
// visitor keys, which svelte-eslint-parser's visitorKeys include). Built once per file.
fn (mut c Checker) sv_steps() []SvelteStep {
	if !c.is_svelte() {
		return []
	}
	if !c.svelte.has_steps {
		c.svelte.steps = sv_steps_from(c.svelte.doc, sv_snode_ref(0))
		c.svelte.has_steps = true
	}
	return c.svelte.steps
}

// sv_snodes are the Svelte nodes in the order the traversal enters them: what the listeners of
// Svelte* node types see.
fn (mut c Checker) sv_snodes() []int {
	if !c.is_svelte() {
		return []
	}
	if !c.svelte.has_snodes {
		mut out := []int{cap: c.svelte.doc.nodes.len}
		for step in c.sv_steps() {
			if !step.leave && !step.node.es {
				out << step.node.idx
			}
		}
		c.svelte.snodes = out
		c.svelte.has_snodes = true
	}
	return c.svelte.snodes
}

// sv_snodes_of are the Svelte nodes of one type, in traversal order.
fn (mut c Checker) sv_snodes_of(typ svelte.SType) []int {
	all := c.sv_snodes()
	doc := c.svelte.doc
	return all.filter(doc.nodes[it].typ == typ)
}

// sv_steps_from walks from `root` with a stack (a template may nest deeply).
fn sv_steps_from(doc &svelte.Document, root svelte.Ref) []SvelteStep {
	mut out := []SvelteStep{cap: (doc.nodes.len + doc.es.nodes.len) * 2}
	mut stack := [SvelteStep{root, false}]
	for stack.len > 0 {
		top := stack.pop()
		out << top
		if top.leave {
			continue
		}
		stack << SvelteStep{top.node, true}
		kids := sv_children(doc, top.node)
		for k := kids.len - 1; k >= 0; k-- {
			stack << SvelteStep{kids[k], false}
		}
	}
	return out
}

fn sv_push_ref(mut out []svelte.Ref, r svelte.Ref) {
	if r.idx >= 0 {
		out << r
	}
}

fn sv_push_snode(mut out []svelte.Ref, i int) {
	if i >= 0 {
		out << sv_snode_ref(i)
	}
}

// sv_children are the children of a node in traversal order (svelte-eslint-parser's
// visitor-keys.ts for the Svelte nodes).
fn sv_children(doc &svelte.Document, r svelte.Ref) []svelte.Ref {
	mut out := []svelte.Ref{}
	if r.es {
		for child in doc.es.children(r.idx) {
			out << sv_es_ref(child)
		}
		return out
	}
	n := &doc.nodes[r.idx]
	match n.typ {
		.program {
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
		}
		.script_element {
			sv_push_ref(mut out, n.name_ref)
			sv_push_snode(mut out, n.start_tag)
			for st in n.body {
				out << sv_es_ref(st)
			}
			sv_push_snode(mut out, n.end_tag)
		}
		.style_element, .element {
			sv_push_ref(mut out, n.name_ref)
			sv_push_snode(mut out, n.start_tag)
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
			sv_push_snode(mut out, n.end_tag)
		}
		.start_tag {
			for a in n.attributes {
				out << sv_snode_ref(a)
			}
		}
		.member_expression_name {
			sv_push_ref(mut out, n.object)
			sv_push_snode(mut out, n.property)
		}
		.mustache_tag, .render_tag, .attach_tag, .spread_attribute {
			sv_push_ref(mut out, n.expression)
		}
		.debug_tag {
			for id in n.identifiers {
				out << sv_es_ref(id)
			}
		}
		.const_tag {
			for d in n.declarations {
				out << sv_es_ref(d)
			}
		}
		.declaration_tag {
			sv_push_ref(mut out, n.declaration)
		}
		.if_block {
			sv_push_ref(mut out, n.expression)
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
			sv_push_snode(mut out, n.else_)
		}
		.else_block, .await_pending_block {
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
		}
		.each_block {
			sv_push_ref(mut out, n.expression)
			sv_push_ref(mut out, n.context)
			sv_push_ref(mut out, n.index_ref)
			sv_push_ref(mut out, n.key_expr)
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
			sv_push_snode(mut out, n.else_)
		}
		.await_block {
			sv_push_ref(mut out, n.expression)
			sv_push_snode(mut out, n.pending)
			sv_push_snode(mut out, n.then)
			sv_push_snode(mut out, n.catch_)
		}
		.await_then_block {
			sv_push_ref(mut out, n.value_es)
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
		}
		.await_catch_block {
			sv_push_ref(mut out, n.error_es)
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
		}
		.key_block {
			sv_push_ref(mut out, n.expression)
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
		}
		.snippet_block {
			sv_push_ref(mut out, n.id)
			for p in n.params {
				out << sv_es_ref(p)
			}
			for ch in n.children {
				out << sv_snode_ref(ch)
			}
		}
		.attribute, .style_directive {
			sv_push_ref(mut out, n.key)
			for v in n.values {
				out << sv_snode_ref(v)
			}
		}
		.shorthand_attribute {
			sv_push_ref(mut out, n.key)
			sv_push_ref(mut out, n.value_ref)
		}
		.directive, .special_directive {
			sv_push_ref(mut out, n.key)
			sv_push_ref(mut out, n.expression)
		}
		.generics_directive {
			sv_push_ref(mut out, n.key)
			for p in n.generic_params {
				out << sv_es_ref(p)
			}
		}
		.directive_key {
			sv_push_ref(mut out, n.key)
		}
		else {}
	}
	return out
}

// sv_ref_range is the range of a node (bytes of the file).
fn (c &Checker) sv_ref_range(r svelte.Ref) (int, int) {
	doc := c.svelte.doc
	if r.es {
		return doc.es.nodes[r.idx].start, doc.es.nodes[r.idx].end
	}
	return doc.nodes[r.idx].start, doc.nodes[r.idx].end
}

// sv_ref_type is a node's `type` (SvelteReactiveStatement for a top-level `$:`).
fn (c &Checker) sv_ref_type(r svelte.Ref) string {
	doc := c.svelte.doc
	if r.es {
		return doc.es_type_name(r.idx)
	}
	return doc.nodes[r.idx].typ.type_name()
}

// sv_text is sourceCode.text.slice(start, end) of the file.
fn (c &Checker) sv_text(start int, end int) string {
	if end <= start {
		return ''
	}
	return c.svelte.doc.src[start..end]
}

// sv_snode_text is sourceCode.getText of a Svelte node.
fn (c &Checker) sv_snode_text(i int) string {
	n := &c.svelte.doc.nodes[i]
	return c.sv_text(n.start, n.end)
}

// sv_es_text is sourceCode.getText of an ESTree node.
fn (c &Checker) sv_es_text(i int) string {
	n := &c.svelte.doc.es.nodes[i]
	return c.sv_text(n.start, n.end)
}

// sv_report is a report on the range [start, end) of the file, located by
// svelte-eslint-parser's locations (a node's or a token's loc).
fn (c &Checker) sv_report(start int, end int, message_id string, data map[string]string) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       data
	}
}

// sv_report_text is a report whose `loc` comes from sourceCode.getLocFromIndex (ESLint's own line
// breaks), not from a node.
fn (c &Checker) sv_report_text(start int, end int, message_id string, data map[string]string) Finding {
	return Finding{
		...c.sv_report(start, end, message_id, data)
		text_loc: true
	}
}

// sv_report_snode is a report on a Svelte node (`node: n`): its loc, whose end may differ from
// its range's (SNode.loc_end).
fn (c &Checker) sv_report_snode(i int, message_id string, data map[string]string) Finding {
	n := &c.svelte.doc.nodes[i]
	end := if n.loc_end >= 0 { n.loc_end } else { n.end }
	return c.sv_report(n.start, end, message_id, data)
}

// sv_report_es is a report on an ESTree node of the document.
fn (c &Checker) sv_report_es(i int, message_id string, data map[string]string) Finding {
	n := &c.svelte.doc.es.nodes[i]
	return c.sv_report(n.start, n.end, message_id, data)
}

// sv_report_ref is a report on a node of either kind.
fn (c &Checker) sv_report_ref(r svelte.Ref, message_id string, data map[string]string) Finding {
	if r.es {
		return c.sv_report_es(r.idx, message_id, data)
	}
	return c.sv_report_snode(r.idx, message_id, data)
}

// sv_report_message is a report with a message of its own (`message:`, no messageId).
fn (c &Checker) sv_report_message(start int, end int, message string) Finding {
	return Finding{
		stmt: c.position_range(start, end)
		text: message
	}
}

// --- utils/svelte-context.ts ---

// SvelteFileType is svelteFileType: a component, a `.svelte.[js|ts]` module, or another file.
enum SvelteFileType {
	none
	component
	module
}

// sv_file_path is the path of the file being linted (a .svelte file's, not its twin's).
fn (c &Checker) sv_file_path(abs_path string) string {
	if c.is_svelte() && abs_path.ends_with(vue_twin_suffix) {
		return abs_path[..abs_path.len - vue_twin_suffix.len]
	}
	return abs_path
}

// sv_file_type is getSvelteFileType of a path.
fn sv_file_type(path string) SvelteFileType {
	return if path.ends_with('.svelte') {
		.component
	} else if path.ends_with('.svelte.js') || path.ends_with('.svelte.ts') {
		.module
	} else {
		.none
	}
}

// sv_rune_names are svelte-eslint-parser's runeSymbols (hasRunesSymbol).
const sv_rune_names = ['\$state', '\$derived', '\$effect', '\$props', '\$bindable', '\$inspect',
	'\$host']

// sv_runes is svelteParseContext.runes of the file being linted, as getSvelteContext gives it (the
// installed Svelte is 5): a component's from `<svelte:options runes={…}>`, else whether an
// Identifier of the document has a rune's name (the compiler decides after parsing); a
// `.svelte.[js|ts]` module is always in runes mode; other files have none (false here).
// svelte.config.js's compilerOptions.runes is not read.
fn (c &Checker) sv_runes() bool {
	if c.svelte_module.on {
		return true
	}
	if !c.is_svelte() {
		return false
	}
	doc := c.svelte.doc
	match doc.runes {
		.on { return true }
		.off { return false }
		else {}
	}
	for i, n in doc.es.nodes {
		if n.typ == .identifier {
			name := doc.es.string_of(i, .name) or { continue }
			if name in sv_rune_names {
				return true
			}
		}
	}
	return false
}

// SvelteKitFileType is svelteKitFileType (getSvelteKitFileTypeFromFilePath).
enum SvelteKitFileType {
	none
	page_svelte   // +page.svelte
	page_ts       // +page.[js|ts]
	page_server   // +page.server.[js|ts]
	error_svelte  // +error.svelte
	layout_svelte // +layout.svelte
	layout_ts     // +layout.[js|ts]
	layout_server // +layout.server.[js|ts]
	server_ts     // +server.[js|ts]
}

fn sv_kit_file_type_of_name(path string) SvelteKitFileType {
	return match os.file_name(path) {
		'+page.svelte' { .page_svelte }
		'+page.js', '+page.ts' { .page_ts }
		'+page.server.js', '+page.server.ts' { .page_server }
		'+error.svelte' { .error_svelte }
		'+layout.svelte' { .layout_svelte }
		'+layout.js', '+layout.ts' { .layout_ts }
		'+layout.server.js', '+layout.server.ts' { .layout_server }
		'+server.js', '+server.ts' { .server_ts }
		else { .none }
	}
}

// SvelteKitContext is the SvelteKit part of getSvelteContext: the major version of
// @sveltejs/kit ('' when the file is in no SvelteKit project) and the kind of route file.
struct SvelteKitContext {
	version   string
	file_type SvelteKitFileType
}

// sv_json_path is the value at a path of objects of a JSON value.
fn sv_json_path(value json2.Any, keys []string) ?json2.Any {
	mut v := value
	for k in keys {
		if v is map[string]json2.Any {
			v = v[k] or { return none }
		} else {
			return none
		}
	}
	return v
}

// sv_kit_context is getSvelteKitContext for a file: the version from the node_modules of
// @sveltejs/kit found from the file's directory up, else from the dependencies of the
// package.json files from there up (eslint-plugin-svelte's own package counts as SvelteKit 2, a
// hack upstream keeps for its tests); the file type when the file is under the routes directory
// (settings.svelte.kit.files.routes, else parserOptions.svelteConfig's, else `src/routes`) of the
// project root (the directory of the closest package.json). svelte.config.js's kit.files.routes is
// not read.
fn (c &Checker) sv_kit_context(path string) SvelteKitContext {
	version := sv_kit_version(path)
	if version == '' {
		return SvelteKitContext{}
	}
	mut routes := 'src/routes'
	mut from_settings := false
	if svelte_settings := c.settings['svelte'] {
		if r := sv_json_path(svelte_settings, ['kit', 'files', 'routes']) {
			if r is string {
				routes = r
				from_settings = true
			}
		}
	}
	if !from_settings && c.language.svelte_kit_routes != '' {
		routes = c.language.svelte_kit_routes
	}
	// `.replace(/^\//, '')`: one leading slash.
	if routes.starts_with('/') {
		routes = routes[1..]
	}
	package_jsons := sv_package_jsons(path)
	root := if package_jsons.len > 0 { os.dir(package_jsons[0]) } else { '' }
	if !path.starts_with(os.join_path(root, routes)) {
		return SvelteKitContext{
			version: version
		}
	}
	return SvelteKitContext{
		version:   version
		file_type: sv_kit_file_type_of_name(path)
	}
}

// sv_package_jsons are the package.json files from the file's directory up (getPackageJsons).
fn sv_package_jsons(path string) []string {
	mut out := []string{}
	mut dir := os.dir(path)
	for {
		candidate := os.join_path(dir, 'package.json')
		if os.is_file(candidate) {
			out << candidate
		}
		parent := os.dir(dir)
		if parent == dir || parent == '' {
			break
		}
		dir = parent
	}
	return out
}

// sv_major_version is extractMajorVersion: the major of a version range (`^2.1.0` -> `2`), and
// with `next` a Kit 1 prerelease (`1.0.0-next`).
fn sv_major_version(version string, next bool) string {
	mut v := version
	if v.starts_with('^') || v.starts_with('~') {
		v = v[1..]
	}
	mut i := 0
	for i < v.len && v[i].is_digit() {
		i++
	}
	if i == 0 || i >= v.len || v[i] != `.` {
		return ''
	}
	if next && v[i..].starts_with('.0.0-next') {
		return v[..i] + '.0.0-next'
	}
	return v[..i]
}

// sv_kit_version is getSvelteKitVersion of a file ('' for none).
fn sv_kit_version(path string) string {
	mut dir := os.dir(path)
	for {
		package_json := os.join_path(dir, 'node_modules', '@sveltejs', 'kit', 'package.json')
		if os.is_file(package_json) {
			text := os.read_file(package_json) or { '' }
			if parsed := json2.decode[json2.Any](text) {
				if v := sv_json_path(parsed, ['version']) {
					if v is string {
						major := sv_major_version(v, true)
						if major != '' {
							return major
						}
					}
				}
			}
			break
		}
		parent := os.dir(dir)
		if parent == dir || parent == '' {
			break
		}
		dir = parent
	}
	for k, file in sv_package_jsons(path) {
		text := os.read_file(file) or { continue }
		parsed := json2.decode[json2.Any](text) or { continue }
		if k == 0 {
			if name := sv_json_path(parsed, ['name']) {
				if name is string && name == 'eslint-plugin-svelte' {
					return '2'
				}
			}
		}
		for section in ['dependencies', 'devDependencies'] {
			if v := sv_json_path(parsed, [section, '@sveltejs/kit']) {
				if v is string {
					major := sv_major_version(v, true)
					if major != '' {
						return major
					}
				}
			}
		}
	}
	return ''
}
