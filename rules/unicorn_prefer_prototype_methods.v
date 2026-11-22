module rules

import estree
import time

// Port of the `unicorn/prefer-prototype-methods` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const uppm_messages = {
	'known-method':   'Prefer using `{{constructorName}}.prototype.{{methodName}}`.'
	'unknown-method': 'Prefer using method from `{{constructorName}}.prototype`.'
}

const uppm_object_prototype_methods = ['hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable',
	'toLocaleString', 'toString', 'valueOf']

fn (mut c Checker) lint_unicorn_prefer_prototype_methods(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	mut trace := map[string]EsTrace{}
	for method in uppm_object_prototype_methods {
		trace[method] = EsTrace{
			read: true
		}
	}
	// globalReferences: the node of each read of a global method, with its path.
	mut global_references := map[int][]string{}
	for traced in c.es_global_references(root, trace) {
		node := c.un_reference_node(t, traced.node) or { continue }
		global_references[node] = traced.path
	}
	for node in 0 .. t.nodes.len {
		if t.typ(node) != .call_expression {
			continue
		}
		stats.checked++
		if finding := c.uppm_problem(t, tokens, node, global_references) {
			findings << finding
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// uppm_problem ports getProblem.
fn (mut c Checker) uppm_problem(t &estree.EsTree, tokens &SourceTokens, call int, global_references map[int][]string) ?Finding {
	mut method_node := -1
	if un_is_method_call(t, call,
		objects:           ['Reflect']
		methods:           ['apply']
		minimum_arguments: 1
		optional_call:     false
		optional_member:   false
	) {
		// `Reflect.apply([].foo, …)`, `Reflect.apply({}.foo, …)`
		method_node = (t.list(call, .arguments) or { return none })[0]
	} else if un_is_method_call(t, call,
		methods:         ['apply', 'bind', 'call']
		optional_call:   false
		optional_member: false
	) {
		// `[].foo.{apply,bind,call}(…)`, `({}).foo.{apply,bind,call}(…)`
		method_node = t.node(t.node(call, .callee)?, .object)?
	}
	if method_node < 0 {
		return none
	}
	// getConstructorAndMethodName
	mut is_global_reference := false
	mut constructor_name := ''
	mut method_name := ?string(none)
	if path := global_references[method_node] {
		is_global_reference = true
		constructor_name = 'Object'
		method_name = path.last()
	} else {
		if !un_is_member(t, method_node, optional: false) {
			return none
		}
		object := t.node(method_node, .object)?
		elements := t.list(object, .elements) or { []int{} }
		properties := t.list(object, .properties) or { []int{} }
		if !((t.typ(object) == .array_expression && elements.len == 0)
			|| (t.typ(object) == .object_expression && properties.len == 0)) {
			return none
		}
		constructor_name = if t.typ(object) == .array_expression { 'Array' } else { 'Object' }
		method_name = c.un_property_name_in(t, method_node)
	}
	mut finding := Finding{
		stmt:       c.es_tree_position(t, method_node)
		message_id: 'unknown-method'
		data:       {
			'constructorName': constructor_name
		}
	}
	if name := method_name {
		finding = Finding{
			...finding
			message_id: 'known-method'
			data:       {
				'constructorName': constructor_name
				'methodName':      name
			}
		}
	}
	// The global reference, or the object literal, is replaced as a whole, a comment inside it would
	// be dropped.
	replaced := if is_global_reference { method_node } else { t.node(method_node, .object)? }
	if tokens.comments_inside(t.nodes[replaced].start, t.nodes[replaced].end).len > 0 {
		return finding
	}
	text := if is_global_reference {
		'${constructor_name}.prototype.${method_name or { '' }}'
	} else {
		'${constructor_name}.prototype'
	}
	mut fixes := [fix_replace_range(t.nodes[replaced].start, t.nodes[replaced].end, text)]
	fixes << c.un_fix_space_around_keyword(t, tokens, call)
	has_fix, fix := c.merge_fixes(fixes) or { return finding }
	return Finding{
		...finding
		has_fix: has_fix
		fix:     fix
	}
}
