module rules

import estree
import json2
import jsregexp
import tsgo { SymbolResponse, TypeResponse }

// Port of the `svelte/no-unused-props` rule of eslint-plugin-svelte 3.24.1: the properties of the
// type of a `$props()` declaration (`let { a }: Props = $props()`, `let props: Props = $props()`)
// that the component never reads are reported on the declaration's id: the destructured names
// and the member paths read from them (through `!`, `as`, `satisfies`, nested destructuring and
// `$derived`), with object spreads using everything below them; nested properties are checked
// too unless `allowUnusedNestedProperties`; an index signature is reported unless a rest element
// takes the remaining props. Properties declared outside the file (unless `checkImportedTypes`),
// of the default libraries, private class members and the types or properties matching the
// ignore patterns are left out, and class types are not looked into. It needs types; its
// condition is runes mode.

const svnup_messages = {
	'unusedProp':           "'{{name}}' is an unused Props property."
	'unusedNestedProp':     "'{{name}}' in '{{parent}}' is an unused property."
	'unusedIndexSignature': 'Index signature is unused. Consider using rest operator (...) to capture remaining properties.'
}

// SvnupPattern is toRegExp of src/utils/regexp.ts: a `/…/flags` string is a regular expression,
// another string is matched whole.
struct SvnupPattern {
	text  string
	regex ?jsregexp.JsRegex
}

fn svnup_pattern(s string) SvnupPattern {
	// /^\/(.+)\/([A-Za-z]*)$/u: `.` does not match line terminators.
	if s.len >= 3 && s[0] == `/` {
		end := s.last_index('/') or { 0 }
		flags := s[end + 1..]
		body := s[1..end]
		if end >= 2 && flags.bytes().all((it >= `a` && it <= `z`) || (it >= `A` && it <= `Z`))
			&& !body.contains_any('\n\r') && !body.contains(' ') && !body.contains(' ') {
			return SvnupPattern{
				text:  s
				regex: jsregexp.js_regex_new(body, flags) or {
					return SvnupPattern{
						text: '\x00'
					}
				}
			}
		}
	}
	return SvnupPattern{
		text: s
	}
}

fn (p &SvnupPattern) test(s string) bool {
	if r := p.regex {
		return r.test(estree.utf16_units(s)) or { false }
	}
	return p.text == s
}

struct SvnupOptions {
	check_imported_types bool
	ignore_types         []SvnupPattern
	ignore_properties    []SvnupPattern
	allow_unused_nested  bool
}

fn svnup_options(options []json2.Any) !SvnupOptions {
	o := option_object(svelte_no_unused_props, options, ['checkImportedTypes', 'ignoreTypePatterns',
		'ignorePropertyPatterns', 'allowUnusedNestedProperties'])!
	return SvnupOptions{
		check_imported_types: o.bool_value('checkImportedTypes')!
		ignore_types:         (o.string_list('ignoreTypePatterns')!).map(svnup_pattern(it))
		ignore_properties:    (o.string_list('ignorePropertyPatterns')!).map(svnup_pattern(it))
		allow_unused_nested:  o.bool_value('allowUnusedNestedProperties')!
	}
}

// SvnupUsed are the property paths read: by name, spread into an object, spread as an iterable.
struct SvnupUsed {
mut:
	paths    [][]string
	object   [][]string
	iterable [][]string
}

struct SvnupContext {
	e      SvscEs
	root   C.vt_node
	o      SvnupOptions
	file   string // the file of the declarations that are internal
	report int    // the declaration's id
mut:
	visited  map[int]bool
	checking []string
	reported map[string]bool
	findings []Finding
}

// svnup_references are the identifiers of the references of an identifier's variable (none when
// it has none, or was looked up before: FindVariableContext).
fn (mut c Checker) svnup_references(mut ctx SvnupContext, id int) ?[]int {
	if ctx.visited[id] {
		return none
	}
	ctx.visited[id] = true
	t := ctx.e.t
	mut out := []int{}
	if ctx.e.svelte {
		v := c.sv_find_variable(id)
		if v < 0 {
			return none
		}
		info := &c.svelte.doc.scope
		for r in info.variables[v].references {
			out << info.references[r].identifier
		}
		return out
	}
	ts := t.ts_node(id)?
	tree := c.scope_tree(ctx.root)
	name := t.string_of(id, .name)?
	scope := tree.get_scope(ts)
	mut v := tree.find_variable(scope, name, t.nodes[id].start)
	if v < 0 && name.starts_with('\$') {
		v = tree.find_variable(scope, name[1..], t.nodes[id].start)
	}
	if v < 0 {
		return none
	}
	for r in tree.variables[v].references {
		out << c.es_index_of(t, tree.references[r].identifier) or { continue }
	}
	return out
}

// svnup_literal_key is String(literal.value) of a string or number Literal.
fn svnup_literal_key(t &estree.EsTree, literal int) ?string {
	value := t.get(literal, .value)
	return match value {
		string { value }
		f64 { js_number_to_string(value) }
		else { none }
	}
}

// svnup_property_path is getPropertyPath: the member path read from a reference, how it is
// spread, and the end node (whose destructuring pattern collectPatternPaths reads).
fn (c &Checker) svnup_property_path(e &SvscEs, id int) ([]string, string, int) {
	t := e.t
	mut paths := []string{}
	mut spread := ''
	mut current := id
	for {
		parent_ref := c.svsc_parent_ref(e, current) or { break }
		if !parent_ref.es {
			if c.svelte.doc.nodes[parent_ref.idx].typ == .spread_attribute {
				spread = 'object'
			}
			break
		}
		parent := parent_ref.idx
		if t.typ(parent) == .member_expression && (t.node(parent, .object) or { -1 }) == current {
			property := t.node(parent, .property) or { break }
			computed := t.flag(parent, .computed) or { false }
			if !computed && t.typ(property) == .identifier {
				paths << t.string_of(property, .name) or { '' }
			} else if t.typ(property) == .literal && svnup_literal_key(t, property) != none {
				paths << svnup_literal_key(t, property) or { '' }
			} else if t.typ(property) == .template_literal
				&& (t.list(property, .expressions) or { []int{} }).len == 0 {
				quasi := (t.list(property, .quasis) or { [-1] })[0]
				value := t.get(quasi, .value)
				if value is estree.TemplateValue {
					paths << if value.has_cooked { value.cooked } else { value.raw }
				}
			} else if computed && t.typ(property) != .literal {
				break
			}
		} else if t.typ(parent) in [.ts_non_null_expression, .ts_as_expression,
			.ts_satisfies_expression]
			&& (t.node(parent, .expression) or { -1 }) == current {
		} else {
			if t.typ(parent) == .spread_element {
				outer := c.svsc_parent(e, parent)
				spread = if outer >= 0 && t.typ(outer) == .object_expression {
					'object'
				} else {
					'iterable'
				}
			}
			break
		}
		current = parent
	}
	return paths, spread, current
}

// svnup_destructuring_pattern is getDestructuringPattern: the object pattern a node (or
// `$derived(node)`) initializes.
fn (c &Checker) svnup_destructuring_pattern(e &SvscEs, node int) int {
	t := e.t
	mut target := node
	parent := c.svsc_parent(e, target)
	if parent >= 0 && t.typ(parent) == .call_expression {
		callee := t.node(parent, .callee) or { -1 }
		args := t.list(parent, .arguments) or { []int{} }
		if callee >= 0 && t.typ(callee) == .identifier
			&& (t.string_of(callee, .name) or { '' }) == '\$derived' && args.len > 0
			&& args[0] == target {
			target = parent
		}
	}
	declarator := c.svsc_parent(e, target)
	if declarator < 0 || t.typ(declarator) != .variable_declarator
		|| (t.node(declarator, .init) or { -1 }) != target {
		return -1
	}
	id := t.node(declarator, .id) or { return -1 }
	return if t.typ(id) == .object_pattern { id } else { -1 }
}

fn svnup_prefixed(prefix []string, paths [][]string) [][]string {
	return paths.map(fn [prefix] (p []string) []string {
		mut out := prefix.clone()
		out << p
		return out
	})
}

// svnup_collect_pattern is collectPatternPaths.
fn (mut c Checker) svnup_collect_pattern(mut ctx SvnupContext, pattern int, prefix []string, mut result SvnupUsed) {
	t := ctx.e.t
	for property in t.list(pattern, .properties) or { []int{} } {
		if t.typ(property) == .rest_element || (t.flag(property, .computed) or { false }) {
			result.object << prefix
			continue
		}
		key := t.node(property, .key) or { continue }
		name := if t.typ(key) == .identifier {
			t.string_of(key, .name) or { '' }
		} else {
			svnup_literal_key(t, key) or { c.svsc_text(&ctx.e, key) }
		}
		mut path := prefix.clone()
		path << name
		mut value := t.node(property, .value) or { continue }
		if t.typ(value) == .assignment_pattern {
			value = t.node(value, .left) or { continue }
		}
		if t.typ(value) == .object_pattern {
			c.svnup_collect_pattern(mut ctx, value, path, mut result)
		} else if t.typ(value) == .identifier {
			nested := c.svnup_used(mut ctx, value)
			result.paths << svnup_prefixed(path, nested.paths)
			result.object << svnup_prefixed(path, nested.object)
			result.iterable << svnup_prefixed(path, nested.iterable)
		} else {
			result.paths << path
		}
	}
}

// svnup_used is getUsedNestedPropertyPathsArray.
fn (mut c Checker) svnup_used(mut ctx SvnupContext, id int) SvnupUsed {
	mut result := SvnupUsed{}
	t := ctx.e.t
	references := c.svnup_references(mut ctx, id) or { return result }
	for identifier in references {
		if t.typ(identifier) != .identifier || (t.nodes[identifier].start == t.nodes[id].start
			&& t.nodes[identifier].end == t.nodes[id].end) {
			continue
		}
		parent := c.svsc_parent(&ctx.e, identifier)
		if parent >= 0 && t.typ(parent) in [.ts_qualified_name, .ts_type_query] {
			continue
		}
		paths, spread, end := c.svnup_property_path(&ctx.e, identifier)
		pattern := c.svnup_destructuring_pattern(&ctx.e, end)
		if pattern >= 0 {
			c.svnup_collect_pattern(mut ctx, pattern, paths, mut result)
		} else if spread == 'object' {
			result.object << paths
		} else if spread == 'iterable' {
			result.iterable << paths
		} else {
			result.paths << paths
		}
	}
	return result
}

fn svnup_at_or_under(path []string, prefix []string) bool {
	if prefix.len > path.len {
		return false
	}
	for i, segment in prefix {
		if path[i] != segment {
			return false
		}
	}
	return true
}

fn svnup_under(path []string, prefix []string) bool {
	return path.len > prefix.len && svnup_at_or_under(path, prefix)
}

// svnup_normalize is normalizeUsedPaths.
fn svnup_normalize(paths [][]string, allow_nested bool) [][]string {
	mut sorted := paths.clone()
	sorted.sort_with_compare(fn (a &[]string, b &[]string) int {
		return a.len - b.len
	})
	mut normalized := [][]string{}
	for path in sorted {
		if normalized.any(svnup_at_or_under(path, it)) {
			continue
		}
		normalized << path
	}
	return normalized.map(if allow_nested && it.len > 0 { [it[0]] } else { it })
}

// svnup_is_class_type is isClassType.
fn (mut c Checker) svnup_is_class_type(t TypeResponse) bool {
	if t.object_flags & 1 != 0 {
		return true
	}
	if t.flags & type_flag_object != 0 && t.object_flags & object_flag_reference != 0 {
		target := c.target_of(t) or { TypeResponse{} }
		if !target.is_null() && target.object_flags & 1 != 0 {
			return true
		}
	}
	if (c.signatures_of(t, signature_kind_construct) or { []SignatureResponse{} }).len > 0 {
		return true
	}
	symbol := c.symbol_of(t) or { return false }
	if symbol.is_null() {
		return false
	}
	return (c.symbol_members(symbol.id) or { []SymbolResponse{} }).any(it.name == 'prototype')
}

// svnup_ignored_type is shouldIgnoreType.
fn (mut c Checker) svnup_ignored_type(ctx &SvnupContext, t TypeResponse) bool {
	if ctx.o.ignore_types.len == 0 {
		return false
	}
	text := c.type_string(t) or { '' }
	if ctx.o.ignore_types.any(it.test(text)) {
		return true
	}
	symbol := c.symbol_of(t) or { return false }
	if symbol.is_null() {
		return false
	}
	name := unescape_name(symbol.name)
	return name != '' && ctx.o.ignore_types.any(it.test(name))
}

// svnup_inaccessible is isInaccessibleClassMember: a `#name`, private or protected member.
fn (mut c Checker) svnup_inaccessible(prop SymbolResponse) bool {
	for declaration in prop.declarations {
		tree := c.declaration_ast(tsgo.handle_path(declaration)) or { continue }
		index := tsgo.handle_index(declaration)
		name := tree.node_child(index, 'name')
		if name != 0 && tree.node_kind(name) == syntax_kind_private_identifier {
			return true
		}
		if tree.node_children(tree.node_child(index, 'modifiers')).any(tree.node_kind(it) in [
			syntax_kind_private_keyword,
			syntax_kind_protected_keyword,
		]) {
			return true
		}
	}
	return false
}

// svnup_index_type is getStringIndexType / getNumberIndexType: the value type of the index
// signature with that key type (a null type for none).
fn (mut c Checker) svnup_index_type(t TypeResponse, key_flag u32) TypeResponse {
	for info in c.index_infos(t.id) or { return TypeResponse{} } {
		if info.key_type.flags == key_flag {
			return info.value_type
		}
	}
	return TypeResponse{}
}

// svnup_check is checkUnusedProperties.
fn (mut c Checker) svnup_check(mut ctx SvnupContext, props_type TypeResponse, used SvnupUsed, declared []string, rest bool, parent_path []string) {
	if ctx.o.allow_unused_nested && parent_path.len > 0 {
		return
	}
	if c.svnup_is_class_type(props_type) {
		return
	}
	text := c.type_string(props_type) or { '' }
	if text in ctx.checking || c.svnup_ignored_type(ctx, props_type) {
		return
	}
	ctx.checking << text
	c.svnup_check_properties(mut ctx, props_type, used, declared, rest, parent_path)
	idx := ctx.checking.index(text)
	if idx >= 0 {
		ctx.checking.delete(idx)
	}
}

// svnup_check_properties is checkPropertiesOfType.
fn (mut c Checker) svnup_check_properties(mut ctx SvnupContext, props_type TypeResponse, used SvnupUsed, declared []string, rest bool, parent_path []string) {
	properties := c.properties(props_type) or { []SymbolResponse{} }
	bases := if props_type.object_flags & object_flags_class_or_interface != 0 {
		c.client.base_types(c.snapshot, c.project, props_type.id) or { []TypeResponse{} }
	} else {
		[]TypeResponse{}
	}
	if properties.len == 0 && bases.len == 0 {
		return
	}
	for base in bases {
		c.svnup_check(mut ctx, base, used, declared, rest, parent_path)
	}
	for prop in properties {
		if prop.declarations.len > 0
			&& (c.is_default_library(tsgo.handle_path(prop.declarations[0])) or { false }) {
			continue
		}
		if c.svnup_inaccessible(prop) {
			continue
		}
		if !ctx.o.check_imported_types && (prop.declarations.len == 0
			|| !prop.declarations.all(tsgo.handle_path(it) == ctx.file)) {
			continue
		}
		name := unescape_name(prop.name)
		if ctx.o.ignore_properties.any(it.test(name)) {
			continue
		}
		mut current := parent_path.clone()
		current << name
		key := json2.encode(current)
		if ctx.reported[key] {
			continue
		}
		if used.object.any(svnup_at_or_under(current, it)) {
			continue
		}
		used_this := used.paths.any(it.len == current.len && svnup_at_or_under(it, current))
			|| used.object.any(svnup_under(it, current))
			|| used.iterable.any(it.len == 0 || svnup_at_or_under(it, current))
		used_in := used.paths.any(svnup_under(it, current))
		if used_this && !used_in {
			continue
		}
		in_props := parent_path.len == 0 && name in declared
		if !used_in && !in_props {
			ctx.reported[key] = true
			e := ctx.e
			ctx.findings << c.svsc_report(&e, ctx.report, if parent_path.len > 0 {
				'unusedNestedProp'
			} else {
				'unusedProp'
			}, {
				'name':   name
				'parent': parent_path.join('.')
			})
			continue
		}
		prop_type := c.symbol_type(prop.id) or { continue }
		c.svnup_check(mut ctx, prop_type, used, declared, rest, current)
	}
	if parent_path.len == 0 {
		string_index := c.svnup_index_type(props_type, type_flag_string)
		number_index := c.svnup_index_type(props_type, type_flag_number)
		has_index := (!string_index.is_null() && string_index.flags & type_flag_any == 0)
			|| (!number_index.is_null() && number_index.flags & type_flag_any == 0)
		if has_index && !rest {
			e := ctx.e
			ctx.findings << c.svsc_report(&e, ctx.report, 'unusedIndexSignature', {})
		}
	}
}

fn (mut c Checker) lint_svelte_no_unused_props(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	o := svnup_options(c.rule_options(svelte_no_unused_props))!
	if !c.svsc_runes_on(abs_path) || !c.scope_setup.type_information
		|| !c.src.contains('\$props') {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	b := c.svsc_bridge(root, &e, abs_path) or { return [] }
	t := e.t
	file := if c.is_svelte() { c.svelte.ts_path } else { abs_path }
	mut findings := []Finding{}
	for i in e.entered() {
		if t.typ(i) != .variable_declarator {
			continue
		}
		declaration := c.svsc_parent(&e, i)
		if declaration < 0 || t.typ(declaration) != .variable_declaration {
			continue
		}
		init := t.node(i, .init) or { continue }
		callee := t.node(init, .callee) or { continue }
		if t.typ(init) != .call_expression || t.typ(callee) != .identifier
			|| (t.string_of(callee, .name) or { '' }) != '\$props' {
			continue
		}
		id := t.node(i, .id) or { continue }
		annotation := t.node(id, .type_annotation) or { continue }
		type_node := t.node(annotation, .type_annotation) or { continue }
		props_type := c.svsc_type_from_type_node(&b, type_node, abs_path, mut stats) or { continue }
		mut ctx := SvnupContext{
			e:      e
			root:   root
			o:      o
			file:   file
			report: id
		}
		mut used := SvnupUsed{}
		mut declared := []string{}
		mut rest := false
		if t.typ(id) == .object_pattern {
			// getUsedPropertyNamesFromPattern: a rest element empties it.
			for p in t.list(id, .properties) or { []int{} } {
				if t.typ(p) == .rest_element {
					rest = true
					declared = []
					break
				}
				if t.typ(p) != .property {
					continue
				}
				key := t.node(p, .key) or { continue }
				value := t.node(p, .value) or { continue }
				if t.typ(key) == .identifier {
					declared << t.string_of(key, .name) or { '' }
				} else if t.typ(key) == .literal && t.typ(value) == .identifier {
					v := t.get(key, .value)
					if v is string {
						declared << v
					}
				}
			}
			if declared.len == 0 {
				continue
			}
			for p in t.list(id, .properties) or { []int{} } {
				if t.typ(p) != .property || (t.flag(p, .computed) or { false }) {
					continue
				}
				key := t.node(p, .key) or { continue }
				prop_name := if t.typ(key) == .identifier {
					t.string_of(key, .name) or { continue }
				} else if t.typ(key) == .literal {
					v := t.get(key, .value)
					if v is string { v } else { continue }
				} else {
					continue
				}
				mut value := t.node(p, .value) or { continue }
				if t.typ(value) == .assignment_pattern {
					value = t.node(value, .left) or { continue }
				}
				if t.typ(value) != .identifier {
					continue
				}
				nested := c.svnup_used(mut ctx, value)
				used.paths << svnup_prefixed([prop_name], nested.paths)
				used.object << svnup_prefixed([prop_name], nested.object)
				used.iterable << svnup_prefixed([prop_name], nested.iterable)
			}
		} else if t.typ(id) == .identifier {
			used = c.svnup_used(mut ctx, id)
		}
		if used.paths.any(it.len == 0) {
			continue
		}
		normalized := SvnupUsed{
			paths:    svnup_normalize(used.paths, o.allow_unused_nested)
			object:   svnup_normalize(used.object, o.allow_unused_nested)
			iterable: svnup_normalize(used.iterable, o.allow_unused_nested)
		}
		c.svnup_check(mut ctx, props_type, normalized, declared, rest || declared.len == 0,
			[]string{})
		findings << ctx.findings
	}
	return findings
}
