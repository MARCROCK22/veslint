module rules

import estree
import time

// Port of the `unicorn/no-useless-error-capture-stack-trace` rule of eslint-plugin-unicorn 64.0.0
// (it has no options), with its fix.

const unuecst_messages = {
	'no-useless-error-capture-stack-trace/error': 'Unnecessary `Error.captureStackTrace(…)` call.'
}

fn (mut c Checker) lint_unicorn_no_useless_error_capture_stack_trace(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	mut classes := []int{}
	mut this_scopes := []int{}
	for step in t.steps() {
		node := step.node
		typ := t.typ(node)
		if typ in [.class_declaration, .class_expression] {
			if step.leave {
				classes.pop()
				this_scopes.pop()
			} else {
				classes << node
				this_scopes << node
			}
			continue
		}
		if typ in [.function_declaration, .function_expression] {
			if step.leave {
				this_scopes.pop()
			} else {
				this_scopes << node
			}
			continue
		}
		if step.leave || typ != .call_expression {
			continue
		}
		stats.checked++
		if classes.len == 0 || this_scopes.len == 0 {
			continue
		}
		class := classes.last()
		if !c.unuecst_builtin_subclass(root, t, class)
			|| !unuecst_class_constructor(t, this_scopes.last(), class)
			|| !un_is_method_call(t, node,
			objects:          ['Error']
			methods:          ['captureStackTrace']
			arguments_length: 2
			optional_member:  false
		) {
			continue
		}
		object := t.node(t.node(node, .callee) or { continue }, .object) or { continue }
		if !c.es_is_global_reference(root, t.ts_node(object) or { continue }) {
			continue
		}
		args := t.list(node, .arguments) or { continue }
		if t.typ(args[0]) != .this_expression || !c.unuecst_class_reference(root, t, args[1], class) {
			continue
		}
		mut finding := Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: 'no-useless-error-capture-stack-trace/error'
		}
		// As upstream, a call in an optional chain is not looked through (it compares the parent
		// with the string 'ChainExpression').
		statement := t.nodes[node].parent
		if t.typ(statement) == .expression_statement
			&& t.typ(t.nodes[statement].parent) == .block_statement {
			finding = Finding{
				...finding
				has_fix: true
				fix:     fix_remove_range(t.nodes[statement].start, t.nodes[statement].end)
			}
		}
		findings << finding
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unuecst_builtin_subclass ports isSubclassOfBuiltinErrors: `class … extends Error` with the
// global error.
fn (mut c Checker) unuecst_builtin_subclass(root C.TSNode, t &estree.EsTree, class int) bool {
	super_class := t.node(class, .super_class) or { return false }
	return t.typ(super_class) == .identifier
		&& (t.string_of(super_class, .name) or { '' }) in un_builtin_errors
		&& c.es_is_global_reference(root, t.ts_node(super_class) or { return false })
}

// unuecst_class_constructor ports isClassConstructor: the function is the constructor of the class.
fn unuecst_class_constructor(t &estree.EsTree, function int, class int) bool {
	method := t.nodes[function].parent
	if method < 0 || t.typ(method) != .method_definition
		|| (t.string_of(method, .kind) or { '' }) != 'constructor'
		|| t.node(method, .value) or { -1 } != function {
		return false
	}
	body := t.node(class, .body) or { return false }
	return method in (t.list(body, .body) or { []int{} })
}

// unuecst_class_reference ports isClassReference: `new.target`, `this.constructor` or the name of
// the class.
fn (mut c Checker) unuecst_class_reference(root C.TSNode, t &estree.EsTree, node int, class int) bool {
	if t.typ(node) == .meta_property {
		meta := t.node(node, .meta) or { return false }
		property := t.node(node, .property) or { return false }
		return (t.string_of(meta, .name) or { '' }) == 'new'
			&& (t.string_of(property, .name) or { '' }) == 'target'
	}
	if un_is_member(t, node, properties: ['constructor'], computed: false, optional: false)
		&& t.typ(t.node(node, .object) or { return false }) == .this_expression {
		return true
	}
	if t.typ(node) != .identifier || t.node(class, .id) == none {
		return false
	}
	ts := t.ts_node(node) or { return false }
	tree := c.scope_tree(root)
	v := tree.find_variable(tree.get_scope(ts), t.string_of(node, .name) or { return false },
		t.nodes[node].start)
	if v < 0 || tree.variables[v].defs.len != 1 {
		return false
	}
	def := tree.variables[v].defs[0]
	class_ts := t.ts_node(class) or { return false }
	return def.kind == .class_name && node_key(def.node) == node_key(class_ts)
}
