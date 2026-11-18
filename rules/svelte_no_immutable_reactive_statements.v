module rules

import estree
import svelte

// Port of the `svelte/no-immutable-reactive-statements` rule of eslint-plugin-svelte 3.24.1: a `$:`
// statement whose top-level variables (those it reads) are all immutable (imports, `const`
// functions and literals, never written variables) is reported, unless it reads a store
// (`$name`), an unknown variable or a `$$` builtin. Its conditions leave runes mode out. It reads
// the document's scope manager; the globals of the configuration (which ESLint resolves the
// references of the global scope's `through` to) come from the lint code's global scope.

const svnirs_messages = {
	'immutable': 'This statement is not reactive because all variables referenced in the reactive statement are immutable.'
}

struct SvnirsState {
mut:
	mutable map[int]bool // isMutableVariable's cache
	visited map[int]bool // FindVariableContext's identifiers
}

// svnirs_is_mutable is isMutableVariable.
fn (c &Checker) svnirs_is_mutable(v int, mut st SvnirsState) bool {
	if cached := st.mutable[v] {
		return cached
	}
	info := &c.svelte.doc.scope
	es := &c.svelte.doc.es
	variable := info.variables[v]
	if variable.defs.len == 0 {
		st.mutable[v] = true
		return true
	}
	mut result := false
	for def in variable.defs {
		kind, node := c.svsc_def(def)
		match kind {
			.import_binding {}
			.computed {
				result = true
			}
			.variable {
				declaration := es.nodes[node].parent
				if (es.string_of(declaration, .kind) or { '' }) == 'const' {
					if init := es.node(node, .init) {
						if es.typ(init) in [.function_expression, .arrow_function_expression, .literal] {
							continue
						}
					}
				} else {
					outer := es.nodes[declaration].parent
					if outer >= 0 && es.typ(outer) == .export_named_declaration
						&& (es.node(outer, .declaration) or { -1 }) == declaration {
						result = true
						break
					}
				}
				mut ctx := SvnirsState{}
				if c.svnirs_has_write(v, mut ctx) {
					result = true
				}
			}
			else {}
		}
		if result {
			break
		}
	}
	st.mutable[v] = result
	return result
}

// svnirs_has_write is hasWrite.
fn (c &Checker) svnirs_has_write(v int, mut ctx SvnirsState) bool {
	info := &c.svelte.doc.scope
	es := &c.svelte.doc.es
	variable := info.variables[v]
	for r in variable.references {
		reference := info.references[r]
		id := reference.identifier
		if reference.write && !variable.defs.any(svsc_in_range(es, id, es.nodes[it.name].start,
			es.nodes[it.name].end)) {
			return true
		}
		if c.svnirs_has_write_member(sv_es_ref(id), mut ctx) {
			return true
		}
	}
	return false
}

// svnirs_has_write_member is hasWriteMember.
fn (c &Checker) svnirs_has_write_member(expr svelte.Ref, mut ctx SvnirsState) bool {
	doc := c.svelte.doc
	es := &doc.es
	parent := c.sv_parent(expr) or { return false }
	if !parent.es {
		p := doc.nodes[parent.idx]
		if p.typ == .directive {
			return p.kind == 'Binding' && p.expression.es == expr.es
				&& p.expression.idx == expr.idx
		}
		if p.typ == .each_block {
			if p.context.idx < 0 || p.expression.es != expr.es || p.expression.idx != expr.idx {
				return false
			}
			return c.svnirs_has_write_reference(p.context, mut ctx)
		}
		return false
	}
	pi := parent.idx
	child := fn [es, expr] (pi int, key estree.Key) bool {
		return expr.es && (es.node(pi, key) or { -1 }) == expr.idx
	}
	return match es.typ(pi) {
		.assignment_expression { child(pi, .left) }
		.update_expression { child(pi, .argument) }
		.unary_expression {
			(es.string_of(pi, .operator) or { '' }) == 'delete' && child(pi, .argument)
		}
		.member_expression { child(pi, .object) && c.svnirs_has_write_member(parent, mut ctx) }
		else { false }
	}
}

// svnirs_has_write_reference is hasWriteReference of a pattern.
fn (c &Checker) svnirs_has_write_reference(pattern svelte.Ref, mut ctx SvnirsState) bool {
	if !pattern.es {
		return false
	}
	for id in svsc_pattern_identifiers(&c.svelte.doc.es, pattern.idx) {
		if ctx.visited[id] {
			continue
		}
		ctx.visited[id] = true
		v := c.sv_find_variable(id)
		if v >= 0 && c.svnirs_has_write(v, mut ctx) {
			return true
		}
	}
	return false
}

fn (mut c Checker) lint_svelte_no_immutable_reactive_statements(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_off(abs_path) {
		return []
	}
	statements := c.svsc_reactive_statements()
	if statements.len == 0 {
		return []
	}
	doc := c.svelte.doc
	es := &doc.es
	info := &doc.scope
	toplevel := c.svsc_toplevel_scope()
	globals := c.scope_tree(root)
	mut st := SvnirsState{}
	mut findings := []Finding{}
	outer: for statement in statements {
		start := es.nodes[statement].start
		end := es.nodes[statement].end
		for v in info.scopes[toplevel].variables {
			for r in info.variables[v].references {
				reference := info.references[r]
				if !svsc_in_range(es, reference.identifier, start, end) {
					continue
				}
				if reference.write && !reference.read {
					continue
				}
				name := es.string_of(reference.identifier, .name) or { '' }
				if name.starts_with('\$') || reference.resolved < 0
					|| c.svnirs_is_mutable(reference.resolved, mut st) {
					continue outer
				}
			}
		}
		for r in info.scopes[toplevel].through {
			reference := info.references[r]
			if !svsc_in_range(es, reference.identifier, start, end) {
				continue
			}
			name := es.string_of(reference.identifier, .name) or { '' }
			if name.starts_with('\$\$') {
				continue outer
			}
			if reference.resolved == -1 && globals.own_variable(0, name) < 0 {
				continue outer
			}
		}
		body := es.node(statement, .body) or { continue }
		mut target := body
		if es.typ(body) == .expression_statement {
			expression := es.node(body, .expression) or { -1 }
			if expression >= 0 && es.typ(expression) == .assignment_expression
				&& (es.string_of(expression, .operator) or { '' }) == '=' {
				target = es.node(expression, .right) or { body }
			}
		}
		findings << c.sv_report_es(target, 'immutable', {})
	}
	return findings
}
