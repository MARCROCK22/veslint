module rules

import codepath
import estree
import jsregexp
import os
import treesitter { Ident, root_node, token_ends }
import vue
import json2
import time

// The wrapper rules of eslint-plugin-vue 10.12.1 (`vue/<rule>`: lib/utils/index.ts's wrapCoreRule
// and wrapStylisticOrCoreRule): a rule of ESLint core or of ESLint Stylistic run on the
// expressions of the template. veslint runs its own port of that rule (the `base`) on each
// template expression, its snippet (vue.Snippet: the code vue-eslint-parser parses, with the
// wrapper that makes it parse, as `0(…)`, and its tree-sitter tree), with:
//   - the Checker on the snippet: its code as the source text, its tree, its ESTree (in the
//     snippet's offsets) and its tokens; and back on the file afterwards (VueWrapSaved);
//   - the nodes the rule's listeners get limited to the ones vue-eslint-parser's traversal visits
//     (EsTree.visit): not the wrapper's, not the type arguments eslint-visitor-keys skips, not those
//     of a dynamic argument with skipDynamicArguments; a rule that walks tree-sitter's tree runs on
//     the subtree of each expression the traversal enters (VueWrap.per_root);
//   - the tokens those of the template token store: the snippet's tokens the document has at the
//     same place with the same text (not the wrapper's);
//   - its reports, fixes and suggestions moved to the file (Snippet.file_offset), the ones that
//     overlap a dynamic argument dropped with skipDynamicArgumentsReport.
// The `Program` listeners of the base rule, which wrapRuleModule moves to the root element of the
// template (or to the document fragment), run once per snippet: the rules ported here only scan
// the tokens there, which the snippets of the template make up between them.
//
// eslint-plugin-vue takes the rule of ESLint Stylistic when @stylistic/eslint-plugin resolves from
// the current directory, and ESLint core's otherwise (vue_wrap_stylistic); veslint's ports are of
// ESLint Stylistic, and `c.vue_wrap_core` tells them to give what the rule of ESLint core gives
// where the two differ.

// VueWrap is the WrapRuleOptions of a wrapper rule, with the rule veslint runs.
struct VueWrap {
	base                          string // the veslint rule run on the template
	apply_document                bool   // applyDocument: the whole document, <style> v-bind() included
	skip_dynamic_arguments        bool   // skipDynamicArguments
	skip_dynamic_arguments_report bool   // skipDynamicArgumentsReport
	// per_root: the base rule walks tree-sitter's tree (nodes_of_kinds) and not the ESTree: it
	// runs on each expression the traversal enters, as the root.
	per_root bool
}

// VueWrapSnippet is a snippet of the template and the ESTree nodes of it the traversal visits.
struct VueWrapSnippet {
	snippet int
mut:
	visited []int // in the order the traversal enters them
	roots   []int // the visited nodes whose parent in the traversal is not one of the snippet
}

// VueWrapSaved is the Checker's file state while a base rule runs on a snippet.
struct VueWrapSaved {
	src                   string
	tokens                treesitter.TokenEnds
	node_index            treesitter.NodeIndex
	file_tokens           &SourceTokens = unsafe { nil }
	file_es_state         EsFileState
	file_es               estree.EsTree
	file_es_by_ts         map[u64]int
	file_code_paths       codepath.Analysis
	file_code_paths_built bool
	file_scopes           &ScopeTree = unsafe { nil }
	vue                   VueView
	has_options           bool
	options               []json2.Any
}

// vue_wrap_stylistic ports getStylisticRule's lookup: @stylistic/eslint-plugin resolves from
// the current directory (a node_modules/@stylistic/eslint-plugin in it or above it, as Node's
// require from there finds it). eslint-plugin-vue also tries @stylistic/eslint-plugin-ts and
// @stylistic/eslint-plugin-js, deprecated packages veslint does not look for. It decides when it
// loads: the answer is kept for the Checker's life.
fn (mut c Checker) vue_wrap_stylistic() bool {
	return c.vue_wrap_stylistic_major() > 0
}

// vue_wrap_stylistic_major is the major version of the @stylistic/eslint-plugin
// vue_wrap_stylistic finds (-1 without one).
fn (mut c Checker) vue_wrap_stylistic_major() int {
	if c.vue_stylistic == 0 {
		c.vue_stylistic = vue_wrap_find_stylistic(os.getwd())
	}
	return c.vue_stylistic
}

// vue_wrap_find_stylistic is the major version of the @stylistic/eslint-plugin found from a
// directory, -1 if none (or 1 when its package.json gives no version veslint reads).
fn vue_wrap_find_stylistic(from string) int {
	mut dir := from
	for {
		if os.base(dir) != 'node_modules' {
			manifest := os.join_path(dir, 'node_modules', '@stylistic', 'eslint-plugin',
				'package.json')
			if os.exists(manifest) {
				text := os.read_file(manifest) or { return 1 }
				decoded := json2.decode[json2.Any](text) or { return 1 }
				if decoded is map[string]json2.Any {
					version := decoded['version'] or { json2.Any('') }
					if version is string {
						major := version.all_before('.').int()
						if major > 0 {
							return major
						}
					}
				}
				return 1
			}
		}
		parent := os.dir(dir)
		if parent == dir || parent == '' {
			return -1
		}
		dir = parent
	}
	return -1
}

// vue_wrap_dynamic_container: the node is the VExpressionContainer of a dynamic argument
// (`VDirectiveKey > VExpressionContainer`).
fn (c &Checker) vue_wrap_dynamic_container(n VueTNode) bool {
	if n.kind != .vnode {
		return false
	}
	node := &c.vue.doc.nodes[n.v]
	return node.typ == .v_expression_container && node.parent >= 0
		&& c.vue.doc.nodes[node.parent].typ == .v_directive_key
}

// vue_wrap_snippets are the snippets of the template (or of the document) with the nodes the
// traversal visits, in the order it enters them.
fn (mut c Checker) vue_wrap_snippets(w VueWrap) []VueWrapSnippet {
	steps := if w.apply_document { c.vue_document_steps() } else { c.vue_template_steps() }
	mut out := []VueWrapSnippet{}
	mut index := map[int]int{}
	mut stack := []VueTNode{}
	mut dynamic := 0
	for step in steps {
		n := step.node
		if step.leave {
			stack.pop()
			if c.vue_wrap_dynamic_container(n) {
				dynamic--
			}
			continue
		}
		if c.vue_wrap_dynamic_container(n) {
			dynamic++
		}
		if n.kind == .estree {
			mut at := index[n.snippet] or { -1 }
			if at < 0 {
				out << VueWrapSnippet{
					snippet: n.snippet
				}
				at = out.len - 1
				index[n.snippet] = at
			}
			if !(w.skip_dynamic_arguments && dynamic > 0) {
				out[at].visited << n.es
				if stack.len == 0 || stack.last().kind != .estree
					|| stack.last().snippet != n.snippet {
					out[at].roots << n.es
				}
			}
		}
		stack << n
	}
	return out
}

// vue_wrap_directive_key_ranges are the ranges of the dynamic arguments
// (wrapContextToOverrideReportMethodToSkipDynamicArgument's directiveKeyRanges).
fn (c &Checker) vue_wrap_directive_key_ranges() [][2]int {
	mut out := [][2]int{}
	for node in c.vue.doc.nodes {
		if node.typ == .v_expression_container && node.parent >= 0
			&& c.vue.doc.nodes[node.parent].typ == .v_directive_key {
			out << [node.start, node.end]!
		}
	}
	return out
}

// vue_wrap_save keeps the Checker's file state; vue_wrap_restore puts it back.
fn (mut c Checker) vue_wrap_save(base string) VueWrapSaved {
	return VueWrapSaved{
		src:                   c.src
		tokens:                c.tokens
		node_index:            c.node_index
		file_tokens:           c.file_tokens
		file_es_state:         c.file_es_state
		file_es:               c.file_es
		file_es_by_ts:         c.file_es_by_ts
		file_code_paths:       c.file_code_paths
		file_code_paths_built: c.file_code_paths_built
		file_scopes:           c.file_scopes
		vue:                   c.vue
		has_options:           base in c.options
		options:               c.options[base] or { []json2.Any{} }
	}
}

fn (mut c Checker) vue_wrap_restore(base string, saved VueWrapSaved) {
	c.src = saved.src
	c.tokens = saved.tokens
	c.node_index = saved.node_index
	c.file_tokens = saved.file_tokens
	c.file_es_state = saved.file_es_state
	c.file_es = saved.file_es
	c.file_es_by_ts = saved.file_es_by_ts
	c.file_code_paths = saved.file_code_paths
	c.file_code_paths_built = saved.file_code_paths_built
	c.file_scopes = saved.file_scopes
	c.vue = saved.vue
	c.vue_wrap_core = false
	if saved.has_options {
		c.options[base] = saved.options
	} else {
		c.options.delete(base)
	}
}

// vue_wrap_doc_has: the document has a token (or a comment) at [start, end) with this text.
fn vue_wrap_doc_has(doc &vue.Document, start int, end int, text string, comment bool) bool {
	list := if comment { doc.comments } else { doc.tokens }
	for i := vue_lower_bound(list, start); i < list.len && list[i].start == start; i++ {
		if list[i].end != end {
			continue
		}
		if comment || list[i].value == text || list[i].typ == 'PrivateIdentifier' {
			return true
		}
	}
	return false
}

// vue_wrap_tokens are the tokens of a snippet the template token store has.
fn vue_wrap_tokens(doc &vue.Document, s &vue.Snippet, root C.TSNode) &SourceTokens {
	all := build_source_tokens(root, s.code)
	mut kept := []SourceToken{cap: all.all.len}
	for t in all.all {
		if vue_wrap_doc_has(doc, s.file_offset(t.start), s.file_offset(t.end), s.code[t.start..t.end],
			t.is_comment()) {
			kept << t
		}
	}
	return &SourceTokens{
		tokens:   kept.filter(!it.is_comment())
		comments: kept.filter(it.is_comment())
		all:      kept
	}
}

// vue_wrap_lint runs the base rule of a wrapper rule on the template: its findings, in the file.
fn (mut c Checker) vue_wrap_lint(rule string, w VueWrap, abs_path string, mut stats Stats) ![]Finding {
	if w.apply_document {
		if !c.is_vue() {
			return []
		}
	} else if !c.vue_has_template() {
		return []
	}
	snippets := c.vue_wrap_snippets(w)
	if snippets.len == 0 {
		return []
	}
	doc := c.vue.doc
	mut options := c.rule_options(rule)
	// The default of dot-location is "property" since ESLint Stylistic 6, "object" before it and
	// in ESLint core.
	if rule == vue_dot_location && options.len == 0 && c.vue_wrap_stylistic_major() < 6 {
		options = [json2.Any('object')]
	}
	key_ranges := if w.skip_dynamic_arguments_report {
		c.vue_wrap_directive_key_ranges()
	} else {
		[][2]int{}
	}
	core := !c.vue_wrap_stylistic()
	mut out := []Finding{}
	for ws in snippets {
		s := &doc.snippets[ws.snippet]
		if s.tree == unsafe { nil } || (w.per_root && ws.roots.len == 0) {
			continue
		}
		top := root_node(s.tree)
		mut es := estree.convert_with(top, s.code, s.tsx, estree.Options{
			module:       true
			regexp_valid: fn (pattern string, flags string) bool {
				return jsregexp.regexp_new(estree.utf16_units(pattern), flags) != none
			}
		}) or { continue }
		mut visit := []bool{len: es.nodes.len}
		for i in ws.visited {
			if i < visit.len {
				visit[i] = true
			}
		}
		es.visit = visit
		tokens := vue_wrap_tokens(doc, s, top)
		// The tokens of the template in the snippet: a report outside them is on the wrapper.
		content_start := if tokens.all.len > 0 { tokens.all[0].start } else { 0 }
		content_end := if tokens.all.len > 0 { tokens.all.last().end } else { 0 }
		saved := c.vue_wrap_save(w.base)
		c.src = s.code
		c.tokens = token_ends(top)
		c.node_index = treesitter.NodeIndex{}
		c.file_tokens = tokens
		c.file_es_state = .built
		c.file_es = es
		c.file_es_by_ts = map[u64]int{}
		c.file_code_paths = codepath.Analysis{}
		c.file_code_paths_built = false
		c.file_scopes = unsafe { nil }
		c.vue = VueView{}
		c.vue_wrap_core = core
		c.options[w.base] = options
		mut found := []Finding{}
		mut failure := ''
		if w.per_root {
			for r in ws.roots {
				if r >= es.nodes.len || !es.nodes[r].has_ts {
					continue
				}
				found << c.vue_wrap_base(w.base, es.nodes[r].ts, abs_path, mut stats) or {
					failure = err.msg()
					break
				}
			}
		} else {
			found = c.vue_wrap_base(w.base, top, abs_path, mut stats) or {
				failure = err.msg()
				[]Finding{}
			}
		}
		mut moved := []Finding{}
		for f in found {
			if f.stmt.start_byte < content_start || f.stmt.start_byte > content_end {
				continue
			}
			moved << c.vue_wrap_move(c.trimmed_end(f.stmt), f, s)
		}
		c.vue_wrap_restore(w.base, saved)
		if failure != '' {
			return error(failure)
		}
		for f in moved {
			if key_ranges.len > 0 && vue_wrap_in_dynamic_argument(f, key_ranges) {
				continue
			}
			out << f
		}
	}
	return out
}

// vue_wrap_move moves a finding of a snippet (its place already trimmed) to the file.
fn (c &Checker) vue_wrap_move(place Ident, f Finding, s &vue.Snippet) Finding {
	return Finding{
		...f
		stmt:        Ident{
			text:       place.text
			start_byte: s.file_offset(place.start_byte)
			row:        if place.row < 0 { place.row } else { 0 }
			end_byte:   if place.end_byte < 0 { -1 } else { s.file_offset(place.end_byte) }
		}
		fix:         vue_wrap_move_fix(f.fix, s)
		suggestions: f.suggestions.map(Suggestion{
			...it
			fix: vue_wrap_move_fix(it.fix, s)
		})
	}
}

fn vue_wrap_move_fix(fix Fix, s &vue.Snippet) Fix {
	return Fix{
		start: s.file_offset(fix.start)
		end:   s.file_offset(fix.end)
		text:  fix.text
	}
}

// vue_wrap_in_dynamic_argument: the report overlaps a dynamic argument (its range, or its start
// alone when it has no end).
fn vue_wrap_in_dynamic_argument(f Finding, ranges [][2]int) bool {
	start := f.stmt.start_byte
	end := if f.stmt.end_byte < 0 { start } else { f.stmt.end_byte }
	for r in ranges {
		if start < r[1] && r[0] < end {
			return true
		}
	}
	return false
}

// vue_wrap_of is the WrapRuleOptions of each wrapper rule (lib/rules/<rule>.ts), with the rule
// veslint runs for it: for the rules of ESLint Stylistic, veslint's port of it, which also gives
// what ESLint core's gives (vue_wrap_core); the bases veslint does not have as rules of their own
// are run by vue_wrap_base.
fn vue_wrap_of(rule string) VueWrap {
	return match rule {
		vue_arrow_spacing {
			VueWrap{
				base: stylistic_arrow_spacing
			}
		}
		vue_camelcase {
			VueWrap{
				base: vue_wrap_camelcase
			}
		}
		vue_comma_dangle {
			VueWrap{
				base: stylistic_comma_dangle
			}
		}
		vue_dot_location {
			VueWrap{
				base: stylistic_dot_location
			}
		}
		vue_no_empty_pattern {
			VueWrap{
				base:     no_empty_pattern
				per_root: true
			}
		}
		vue_no_sparse_arrays {
			VueWrap{
				base:     no_sparse_arrays
				per_root: true
			}
		}
		vue_operator_linebreak {
			VueWrap{
				base: vue_wrap_operator_linebreak
			}
		}
		vue_array_bracket_newline {
			VueWrap{
				base:                   vue_wrap_array_bracket_newline
				skip_dynamic_arguments: true
			}
		}
		vue_array_bracket_spacing {
			VueWrap{
				base:                   stylistic_array_bracket_spacing
				skip_dynamic_arguments: true
			}
		}
		vue_array_element_newline {
			VueWrap{
				base:                   vue_wrap_array_element_newline
				skip_dynamic_arguments: true
			}
		}
		vue_block_spacing {
			VueWrap{
				base:                   stylistic_block_spacing
				skip_dynamic_arguments: true
			}
		}
		vue_brace_style {
			VueWrap{
				base:                   stylistic_brace_style
				skip_dynamic_arguments: true
			}
		}
		vue_dot_notation {
			// ESLint Stylistic has no dot-notation: ESLint core's, always.
			VueWrap{
				base:           core_dot_notation
				apply_document: true
				per_root:       true
			}
		}
		vue_eqeqeq {
			VueWrap{
				base:           eqeqeq
				apply_document: true
				per_root:       true
			}
		}
		vue_key_spacing {
			VueWrap{
				base:                   stylistic_key_spacing
				skip_dynamic_arguments: true
			}
		}
		vue_keyword_spacing {
			VueWrap{
				base:                   stylistic_keyword_spacing
				skip_dynamic_arguments: true
			}
		}
		vue_no_restricted_syntax {
			VueWrap{
				base:           no_restricted_syntax
				apply_document: true
			}
		}
		vue_no_useless_concat {
			VueWrap{
				base:           no_useless_concat
				apply_document: true
				per_root:       true
			}
		}
		vue_object_curly_newline {
			VueWrap{
				base:                   stylistic_object_curly_newline
				skip_dynamic_arguments: true
			}
		}
		vue_object_curly_spacing {
			VueWrap{
				base:                   stylistic_object_curly_spacing
				skip_dynamic_arguments: true
			}
		}
		vue_object_property_newline {
			VueWrap{
				base:                   stylistic_object_property_newline
				skip_dynamic_arguments: true
			}
		}
		vue_prefer_template {
			VueWrap{
				base:           prefer_template
				apply_document: true
				per_root:       true
			}
		}
		vue_no_implicit_coercion {
			VueWrap{
				base:           no_implicit_coercion
				apply_document: true
				per_root:       true
			}
		}
		vue_no_loss_of_precision {
			VueWrap{
				base:           no_loss_of_precision
				apply_document: true
				per_root:       true
			}
		}
		vue_no_negated_condition {
			VueWrap{
				base:           no_negated_condition
				apply_document: true
			}
		}
		vue_object_shorthand {
			VueWrap{
				base:                   object_shorthand
				skip_dynamic_arguments: true
				per_root:               true
			}
		}
		vue_space_infix_ops {
			VueWrap{
				base:                   stylistic_space_infix_ops
				skip_dynamic_arguments: true
				apply_document:         true
			}
		}
		vue_space_unary_ops {
			VueWrap{
				base:                   stylistic_space_unary_ops
				skip_dynamic_arguments: true
				apply_document:         true
			}
		}
		vue_template_curly_spacing {
			VueWrap{
				base:                   stylistic_template_curly_spacing
				skip_dynamic_arguments: true
				apply_document:         true
			}
		}
		vue_comma_spacing {
			VueWrap{
				base:                          stylistic_comma_spacing
				skip_dynamic_arguments:        true
				skip_dynamic_arguments_report: true
				apply_document:                true
			}
		}
		vue_multiline_ternary {
			VueWrap{
				base:                   stylistic_multiline_ternary
				skip_dynamic_arguments: true
				apply_document:         true
			}
		}
		vue_space_in_parens {
			VueWrap{
				base:                          stylistic_space_in_parens
				skip_dynamic_arguments:        true
				skip_dynamic_arguments_report: true
				apply_document:                true
			}
		}
		vue_func_call_spacing {
			VueWrap{
				base:                   stylistic_function_call_spacing
				skip_dynamic_arguments: true
				apply_document:         true
			}
		}
		vue_comma_style {
			VueWrap{
				base: stylistic_comma_style
			}
		}
		vue_no_constant_condition {
			VueWrap{
				base:     no_constant_condition
				per_root: true
			}
		}
		vue_no_console {
			// skipBaseHandlers: only the MemberExpression listener of the wrapper's create.
			VueWrap{
				base: vue_wrap_no_console
			}
		}
		vue_quote_props {
			VueWrap{
				base:                   stylistic_quote_props
				skip_dynamic_arguments: true
			}
		}
		vue_no_extra_parens {
			VueWrap{
				base:                   stylistic_no_extra_parens
				skip_dynamic_arguments: true
				apply_document:         true
			}
		}
		else {
			VueWrap{}
		}
	}
}

// The bases veslint has no rule of its own for (run by vue_wrap_base).
const vue_wrap_camelcase = 'camelcase'
const vue_wrap_operator_linebreak = '@stylistic/operator-linebreak'
const vue_wrap_array_bracket_newline = '@stylistic/array-bracket-newline'
const vue_wrap_array_element_newline = '@stylistic/array-element-newline'
const vue_wrap_no_console = 'vue/no-console:base'

// vue_wrap_base runs a base rule on the snippet the Checker is on.
fn (mut c Checker) vue_wrap_base(base string, root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return match base {
		vue_wrap_no_console { c.vue_wrap_no_console_base(root, abs_path, mut stats)! }
		vue_wrap_camelcase { c.lint_camelcase_base(root, abs_path, mut stats)! }
		vue_wrap_operator_linebreak { c.lint_stylistic_operator_linebreak(root, abs_path, mut stats)! }
		vue_wrap_array_bracket_newline { c.lint_stylistic_array_bracket_newline(root, abs_path, mut stats)! }
		vue_wrap_array_element_newline { c.lint_stylistic_array_element_newline(root, abs_path, mut stats)! }
		else { c.lint_rule(base, root, abs_path, mut stats)! }
	}
}

// lint_vue_wrap lints a wrapper rule.
fn (mut c Checker) lint_vue_wrap(rule string, abs_path string, mut stats Stats) ![]Finding {
	if !c.is_vue() {
		return []
	}
	sw := time.new_stopwatch()
	findings := c.vue_wrap_lint(rule, vue_wrap_of(rule), abs_path, mut stats)!
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// vue_wrap_base_rule is the veslint rule a wrapper rule runs, when it is one (the options of the
// wrapper are those of that rule: its meta, defaultOptions included, is the wrapper's).
pub fn vue_wrap_base_rule(rule string) ?string {
	if !rule.starts_with('vue/') {
		return none
	}
	base := vue_wrap_of(rule).base
	// dot-location's default depends on the rule it wraps (vue_wrap_lint): its options are taken
	// as written.
	if base == '' || base.starts_with('vue/') || base !in names || rule == vue_dot_location {
		return none
	}
	return base
}
