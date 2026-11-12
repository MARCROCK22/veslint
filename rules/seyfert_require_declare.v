module rules

import time
import tsgo { SymbolResponse }
import treesitter { node_field, position_of }

// Port of the `require-declare` rule of @slipher/eslint-plugin 1.1.0 (it has no options): a class
// that is not abstract and extends one of seyfert's command bases, without seyfert's `@Declare`,
// unless it may inherit one from a class of the program.

const sy_rd_messages = {
	'missingDeclare': 'This class extends a Seyfert command but is missing the `@Declare` decorator.'
}

fn (mut c Checker) lint_seyfert_require_declare(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	// The classes with a superClass (an abstract class is skipped).
	mut classes := []C.TSNode{}
	mut supers := []C.TSNode{}
	mut asked := []C.TSNode{}
	for node in c.nodes_of_kinds(root, ['class_declaration', 'class'], []) {
		value := cm_super_class(node) or { continue }
		super_class := unwrap_parens(value)
		classes << node
		supers << super_class
		asked << super_class
		for decorator in cm_class_decorators(node) {
			if callee := sy_decorator_callee(decorator) {
				asked << callee
			}
		}
	}
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(asked)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for i, node in classes {
		super_type := c.sy_instance_type(supers[i])!
		if super_type.is_null() || !c.sy_extends_class(super_type, sy_command_bases)! {
			continue
		}
		if c.sy_has_decorator(cm_class_decorators(node), 'Declare')! {
			continue
		}
		class := sy_class_of_extends(c.sy_node_at(supers[i])!)
		if !class.exists() || sy_is_ambient(class) || c.sy_rd_may_inherit_declare(class)! {
			continue
		}
		name := node_field(node, 'name') or { node }
		findings << Finding{
			stmt:       position_of(name)
			message_id: 'missingDeclare'
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += classes.len
	return findings
}

// sy_class_of_extends is the class (of tsgo's AST) whose `extends` clause has that expression.
fn sy_class_of_extends(expression SyNode) SyNode {
	mut node := expression
	for _ in 0 .. 4 {
		node = node.parent()
		if !node.exists() {
			break
		}
		if node.kind() in [sy_kind_class_declaration, sy_kind_class_expression] {
			return node
		}
	}
	return SyNode{}
}

// sy_extends_expression is the expression of the first type of the `extends` clause of a class
// (heritageClauses.find(extends).types[0].expression).
fn sy_extends_expression(class SyNode) SyNode {
	for clause in class.list('heritageClauses') {
		if clause.tree.node_token(clause.index) == sy_kind_extends_keyword {
			types := clause.list('types')
			return if types.len > 0 { types[0].child('expression') } else { SyNode{} }
		}
	}
	return SyNode{}
}

const sy_kind_extends_keyword = u32(95)

// sy_is_ambient ports isAmbient: a class of a declaration file, or with `declare`.
fn sy_is_ambient(class SyNode) bool {
	return sy_is_declaration_file(class.tree.path) || class.has_modifier(sy_kind_declare_keyword)
}

// sy_is_declaration_file ports isDeclarationFileName: `.d.ts`, `.d.mts`, `.d.cts`, or a `.ts` file
// whose name has `.d.` (`x.d.css.ts`).
fn sy_is_declaration_file(path string) bool {
	if path.ends_with('.d.ts') || path.ends_with('.d.mts') || path.ends_with('.d.cts') {
		return true
	}
	return path.ends_with('.ts') && path.all_after_last('/').contains('.d.')
}

// sy_rd_may_inherit_declare ports mayInheritDeclare: following the `extends` of the class through
// the classes of the program, one of them has seyfert's `@Declare`, or the chain leaves what can be
// read (a base that is not a class, an ambient class, a cycle) before it reaches a seyfert class.
fn (mut c Checker) sy_rd_may_inherit_declare(node SyNode) !bool {
	mut seen := map[string]bool{}
	mut current := node
	for {
		base := sy_extends_expression(current)
		symbol := if base.exists() { c.sy_symbol_of(base)! } else { SymbolResponse{} }
		if c.sy_export_name(symbol)! != '' {
			return false
		}
		if symbol.is_null() {
			return true
		}
		declaration := c.sy_node_of_handle(c.sy_unalias(symbol)!.value_declaration)!
		if !declaration.exists()
			|| declaration.kind() !in [sy_kind_class_declaration, sy_kind_class_expression]
			|| sy_is_ambient(declaration) {
			return true
		}
		key := declaration.handle()
		if key in seen {
			return true
		}
		seen[key] = true
		for decorator in declaration.decorators() {
			if c.sy_is_seyfert(c.sy_symbol_of(sy_decorator_ts_callee(decorator))!, 'Declare')! {
				return true
			}
		}
		current = declaration
	}
	return true
}
