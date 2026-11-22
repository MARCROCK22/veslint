module rules

import estree
import treesitter { named_children, node_field, node_kind, node_parent }

// The component detection of eslint-plugin-vue 10.12.1's lib/utils/index.ts, for the script
// rules (executeOnVue, executeOnVueComponent, executeOnVueInstance, executeOnCallVueComponent,
// defineVueVisitor, getVueObjectType, getVueComponentDefinitionType, isSFCObject…) and the AST
// helpers they use (findProperty, getStaticPropertyName, getStringLiteralValue,
// skipTSAsExpression, isThis, iterateProperties, iterateWatchHandlerValues, the props, emits
// and computed properties of the options…), on the file's ESTree (estree_bridge.v). They run on
// every file a vue/* script rule lints, as upstream: a `.ts` file has components too
// (`Vue.component('x', {…})`, `defineComponent({…})`, a `// @vue/component` comment).
//
// What every rule asks (the type of each ObjectExpression, the Vue object a node is in, the
// `<script setup>` element) is computed once per file into a VueScript (Checker.vue_script),
// which reset_es_file forgets. The macros of `<script setup>` are in vue_script_setup.v.

// VueObjectType is getVueObjectType's answer for an ObjectExpression (VueObjectType of
// lib/utils): `none_` when it is not a Vue object.
enum VueObjectType as u8 {
	none_
	mark       // after a `@vue/component` comment
	export     // `export default {…}` of a .vue, .jsx or .tsx file
	definition // `Vue.component('x', {…})`, `app.mixin({…})`, `defineComponent({…})`…
	instance   // `new Vue({…})`
}

// vue_object_type_name is the type as upstream names it.
fn vue_object_type_name(t VueObjectType) string {
	return match t {
		.none_ { '' }
		.mark { 'mark' }
		.export { 'export' }
		.definition { 'definition' }
		.instance { 'instance' }
	}
}

// VueScript is what the script rules share about the file being linted.
struct VueScript {
mut:
	built bool
	// is_vue_file is isVueFile(context.filename): the name ends with .vue, .jsx or .tsx.
	is_vue_file bool
	filename    string
	// types is getVueObjectType of each ObjectExpression, by ESTree node.
	types []VueObjectType
	// owner is, for each ESTree node, the innermost Vue object that contains it (itself
	// included), -1 for none: defineVueVisitor's vueStack.node when the node's listeners run.
	owner []int
	// objects are the Vue objects in the order of their `ObjectExpression:exit` (where
	// executeOnVue and its siblings call back).
	objects []int
	// The `<script setup>` element (getScriptSetupElement): its range, when has_setup.
	has_setup     bool
	setup_element int = -1
	setup_start   int
	setup_end     int
	// The compiler macros of `<script setup>` (vue_script_setup.v), built on first use.
	macros       []VueMacro
	macros_built bool
	// is_global_or_imported_from_vue of each callee name.
	vue_callees map[string][]int
}

// vue_script is the VueScript of the file, built on first use; none when the file has no ESTree
// (syntax errors).
fn (mut c Checker) vue_script(root C.vt_node, abs_path string) ?&VueScript {
	t := c.es_tree(root, abs_path)?
	if !c.vue_script_info.built {
		filename := c.vue_context_filename(abs_path)
		c.vue_script_info = VueScript{
			built:       true
			is_vue_file: filename.ends_with('.vue') || filename.ends_with('.jsx')
				|| filename.ends_with('.tsx')
			filename:    filename
		}
		c.vue_build_script_setup()
		c.vue_build_objects(root, t)
	}
	return &c.vue_script_info
}

// vue_context_filename is context.filename: the rules get the path of a .vue file's twin
// (vue_file.v), whose name is the .vue's with vue_twin_suffix after it.
fn (c &Checker) vue_context_filename(abs_path string) string {
	return if c.is_vue() { abs_path.trim_string_right(vue_twin_suffix) } else { abs_path }
}

// vue_build_script_setup ports getScriptSetupElement: of two top-level <script> elements the one
// with a `setup` attribute, of one that one if it has it.
fn (mut c Checker) vue_build_script_setup() {
	if !c.is_vue() {
		return
	}
	doc := c.vue.doc
	scripts := doc.top_elements('script')
	mut element := -1
	if scripts.len == 2 {
		for s in scripts {
			if c.vue_has_attribute(s, 'setup', none) {
				element = s
				break
			}
		}
	} else if scripts.len > 0 && c.vue_has_attribute(scripts[0], 'setup', none) {
		element = scripts[0]
	}
	if element >= 0 {
		c.vue_script_info.has_setup = true
		c.vue_script_info.setup_element = element
		c.vue_script_info.setup_start = doc.nodes[element].start
		c.vue_script_info.setup_end = doc.nodes[element].end
	}
}

// vue_in_script_setup is isInScriptSetup of defineScriptSetupVisitor: the node is inside the
// `<script setup>` element.
fn (s &VueScript) in_script_setup(t &estree.EsTree, node int) bool {
	return s.has_setup && s.setup_start <= t.nodes[node].start && t.nodes[node].end <= s.setup_end
}

// vue_build_objects gives every ObjectExpression its type, and every node its Vue object.
fn (mut c Checker) vue_build_objects(root C.vt_node, t &estree.EsTree) {
	n := t.nodes.len
	c.vue_script_info.types = []VueObjectType{len: n}
	c.vue_script_info.owner = []int{len: n, init: -1}
	comment_lines := c.vue_component_comment_lines(t)
	mut stack := []int{}
	for step in t.steps() {
		node := step.node
		if step.leave {
			if stack.len > 0 && stack.last() == node {
				stack.pop()
				c.vue_script_info.objects << node
			}
			continue
		}
		if t.typ(node) == .object_expression {
			typ := c.vue_get_object_type(root, t, node, comment_lines)
			c.vue_script_info.types[node] = typ
			if typ != .none_ {
				stack << node
			}
		}
		if stack.len > 0 {
			c.vue_script_info.owner[node] = stack.last()
		}
	}
}

// vue_component_comment_lines are the lines where getComponentComments' comments (those whose
// value has `@vue/component`) end.
fn (mut c Checker) vue_component_comment_lines(t &estree.EsTree) map[int]bool {
	mut lines := map[int]bool{}
	tokens := c.un_tokens(t)
	for comment in tokens.comments {
		if c.src[comment.start..comment.end].contains('@vue/component') {
			line, _ := t.line_column(comment.end)
			lines[line] = true
		}
	}
	return lines
}

// vue_get_object_type ports getVueObjectType.
fn (mut c Checker) vue_get_object_type(root C.vt_node, t &estree.EsTree, node int, comment_lines map[int]bool) VueObjectType {
	parent := vue_get_parent(t, node)
	if parent >= 0 {
		match t.typ(parent) {
			.export_default_declaration {
				declaration := t.node(parent, .declaration) or { -1 }
				if c.vue_script_info.is_vue_file && declaration >= 0
					&& t.typ(declaration) == .object_expression
					&& vue_skip_ts_as(t, declaration) == node {
					s := &c.vue_script_info
					// `export default` in `<script setup>` is not a component.
					if s.has_setup && s.setup_start <= t.nodes[parent].start
						&& t.nodes[parent].end <= s.setup_end {
						return .none_
					}
					return .export
				}
			}
			.call_expression {
				args := t.list(parent, .arguments) or { []int{} }
				if args.len > 0 && vue_skip_ts_as(t, args.last()) == node
					&& c.vue_component_definition_type(root, t, node) != '' {
					return .definition
				}
			}
			.new_expression {
				args := t.list(parent, .arguments) or { []int{} }
				if vue_is_vue_instance(t, parent) && vue_skip_ts_as(t, args[0]) == node {
					return .instance
				}
			}
			else {}
		}
	}
	line, _ := t.line_column(t.nodes[node].start)
	return if comment_lines[line - 1] { .mark } else { .none_ }
}

// vue_component_definition_type ports getVueComponentDefinitionType: 'component', 'mixin',
// 'extend', 'createApp', 'defineComponent', 'defineNuxtComponent' or '' (null).
fn (mut c Checker) vue_component_definition_type(root C.vt_node, t &estree.EsTree, node int) string {
	parent := vue_get_parent(t, node)
	if parent < 0 || t.typ(parent) != .call_expression {
		return ''
	}
	callee := t.node(parent, .callee) or { return '' }
	if t.typ(callee) == .member_expression {
		object := vue_skip_ts_as(t, t.node(callee, .object) or { return '' })
		if t.typ(object) != .identifier {
			return ''
		}
		prop_name := vue_static_property_name(t, callee) or { '' }
		if prop_name == '' || !vue_is_object_argument(t, parent) {
			return ''
		}
		if (t.string_of(object, .name) or { '' }) == 'Vue' {
			// Vue.js 2: Vue.component('xxx', {}), Vue.mixin({}), Vue.extend('xxx', {})
			return if prop_name in ['component', 'mixin', 'extend'] { prop_name } else { '' }
		}
		// Vue.js 3: app.component('xxx', {}), app.mixin({})
		return if prop_name in ['component', 'mixin'] { prop_name } else { '' }
	}
	if t.typ(callee) == .identifier {
		name := t.string_of(callee, .name) or { '' }
		if name == 'defineNuxtComponent' {
			return if vue_is_object_argument(t, parent) { name } else { '' }
		}
		if name in ['component', 'createApp', 'defineComponent']
			&& c.vue_is_global_or_imported_from_vue(root, t, callee) {
			return if vue_is_object_argument(t, parent) { name } else { '' }
		}
	}
	return ''
}

// vue_is_object_argument ports isObjectArgument: the last argument is an object (through `as`).
fn vue_is_object_argument(t &estree.EsTree, call int) bool {
	args := t.list(call, .arguments) or { return false }
	return args.len > 0 && t.typ(vue_skip_ts_as(t, args.last())) == .object_expression
}

// vue_is_vue_instance ports isVueInstance: `new Vue({…})`.
fn vue_is_vue_instance(t &estree.EsTree, node int) bool {
	callee := t.node(node, .callee) or { return false }
	args := t.list(node, .arguments) or { return false }
	return t.typ(callee) == .identifier && (t.string_of(callee, .name) or { '' }) == 'Vue'
		&& args.len > 0 && t.typ(vue_skip_ts_as(t, args[0])) == .object_expression
}

// vue_composition_modules are the modules of createCompositionApiTraceMap.
const vue_composition_modules = ['vue', '@vue/composition-api', '@nuxtjs/composition-api', '#imports']

// VueTracedCall is a call iterateReferencesTraceMap reports: the CallExpression and the name it
// calls.
struct VueTracedCall {
	call int
	name string
}

// vue_composition_api_calls ports iterateReferencesTraceMap(tracker,
// createCompositionApiTraceMap({ [name]: { [ReferenceTracker.CALL]: true }, … })): the
// CallExpressions of the names imported from the composition API modules, then of the globals.
fn (mut c Checker) vue_composition_api_calls(root C.vt_node, t &estree.EsTree, names []string) []VueTracedCall {
	call_trace := EsTrace{
		call: true
	}
	mut children := map[string]EsTrace{}
	for name in names {
		children[name] = call_trace
	}
	esm := EsTrace{
		esm:      true
		children: children
	}
	mut esm_map := map[string]EsTrace{}
	for module in vue_composition_modules {
		esm_map[module] = esm
	}
	mut traced := c.es_esm_references(root, esm_map)
	traced << c.es_global_references(root, children)
	mut out := []VueTracedCall{}
	mut seen := map[int]bool{}
	for r in traced {
		if r.kind != 'call' || r.path.len == 0 {
			continue
		}
		call := c.es_index_of(t, r.node) or { continue }
		if t.typ(call) == .call_expression && call !in seen {
			seen[call] = true
			out << VueTracedCall{call, r.path.last()}
		}
	}
	return out
}

// vue_like_packages are the modules isGlobalOrImportedFromVue takes an import or a require from.
const vue_like_packages = ['vue', '@vue/composition-api', '@nuxtjs/composition-api']

// vue_is_global_or_imported_from_vue ports isGlobalOrImportedFromVue: the callee (an Identifier)
// calls the global or the export of Vue of its name, or nothing tells it is something else.
fn (mut c Checker) vue_is_global_or_imported_from_vue(root C.vt_node, t &estree.EsTree, callee int) bool {
	name := t.string_of(callee, .name) or { return true }
	call := t.nodes[callee].parent
	calls := c.vue_traced_calls(root, t, name)
	if call in calls {
		return true
	}
	// No reference found: the callee is from another source, or injected.
	tree := c.scope_tree(root)
	v := c.unb_find_variable(root, t, callee)
	if v >= 0 && tree.variables[v].defs.len == 1 {
		def := tree.variables[v].defs[0]
		match def.kind {
			.import_binding {
				// import { name } from 'not-vue'
				if node_kind(def.node) == 'import_specifier' {
					imported := node_field(def.node, 'name') or { return true }
					if node_kind(imported) == 'identifier' {
						statement := vue_import_statement_of(def.node) or { return true }
						source := node_field(statement, 'source') or { return true }
						return (c.string_if_constant_unscoped(source) or { '' }) in vue_like_packages
					}
				}
			}
			.variable {
				// const { name } = require('something')
				id := def.decl_id or { return true }
				init := def.init or { return true }
				if node_kind(id) == 'object_pattern' {
					call_node := unwrap_parens(init)
					if node_kind(call_node) == 'call_expression' {
						function := unwrap_parens(node_field(call_node, 'function') or {
							return true
						})
						if node_kind(function) == 'identifier' && c.text(function) == 'require' {
							args := named_children(node_field(call_node, 'arguments') or {
								return false
							})
							if args.len == 0 {
								return false
							}
							es_first := c.es_index_of(t, args[0]) or { return false }
							if !vue_is_string_literal(t, es_first) {
								return false
							}
							source := vue_string_literal_value(t, es_first, false) or { return false }
							return source in vue_like_packages
						}
					}
				}
			}
			.catch_clause, .class_name, .function_name {
				return false
			}
			else {}
		}
	}
	// Cannot tell the source: true.
	return true
}

// vue_import_statement_of is the import statement an import specifier is in.
fn vue_import_statement_of(n C.vt_node) ?C.vt_node {
	mut node := n
	for {
		node = node_parent(node)?
		if node_kind(node) == 'import_statement' {
			return node
		}
	}
	return none
}

// vue_traced_calls are the calls isGlobalOrImportedFromVue's ReferenceTracker finds of `name`
// (as a global, an import of the composition API modules, or a property of their require()),
// as ESTree nodes; once per name and file.
fn (mut c Checker) vue_traced_calls(root C.vt_node, t &estree.EsTree, name string) []int {
	if cached := c.vue_script_info.vue_callees[name] {
		return cached
	}
	call_trace := EsTrace{
		call: true
	}
	mut traced := c.es_global_references(root, {
		name: call_trace
	})
	esm := EsTrace{
		esm:      true
		children: {
			name: call_trace
		}
	}
	cjs := EsTrace{
		children: {
			name: call_trace
		}
	}
	mut esm_map := map[string]EsTrace{}
	mut cjs_map := map[string]EsTrace{}
	for module in vue_composition_modules {
		esm_map[module] = esm
		cjs_map[module] = cjs
	}
	traced << c.es_esm_references(root, esm_map)
	traced << c.es_cjs_references(root, cjs_map)
	mut out := []int{}
	for r in traced {
		if r.kind == 'call' {
			if i := c.es_index_of(t, r.node) {
				out << i
			}
		}
	}
	c.vue_script_info.vue_callees[name] = out
	return out
}

// vue_object_type is getVueObjectType of an ObjectExpression of the file.
fn (s &VueScript) object_type(node int) VueObjectType {
	return if node >= 0 && node < s.types.len { s.types[node] } else { .none_ }
}

// vue_objects_of are the Vue objects of the file whose type is one of `types`, in the order of
// their `ObjectExpression:exit`: executeOnVue (all), executeOnVueComponent (mark, export,
// definition) and executeOnVueInstance (instance).
fn (s &VueScript) objects_of(types []VueObjectType) []int {
	return s.objects.filter(s.types[it] in types)
}

const vue_all_object_types = [VueObjectType.mark, .export, .definition, .instance]
const vue_component_object_types = [VueObjectType.mark, .export, .definition]

// vue_owner is defineVueVisitor's vueStack.node when the listeners of `node` run: the innermost
// Vue object that contains it, -1 for none.
fn (s &VueScript) owner_of(node int) int {
	return if node >= 0 && node < s.owner.len { s.owner[node] } else { -1 }
}

// vue_vue_object_function_kind ports the `Property[value.type=/^(Arrow)?FunctionExpression$/] >
// :function` listener of defineVueVisitor: 'setup' or 'render' when the function is the value of
// a property of that name of the Vue object it is in (onSetupFunctionEnter,
// onRenderFunctionEnter), '' otherwise.
fn (s &VueScript) vue_function_kind(t &estree.EsTree, node int) string {
	if t.typ(node) !in [.function_expression, .arrow_function_expression] {
		return ''
	}
	prop := t.nodes[node].parent
	if prop < 0 || t.typ(prop) != .property || (t.node(prop, .value) or { -1 }) != node {
		return ''
	}
	owner := s.owner_of(node)
	if owner < 0 || t.nodes[prop].parent != owner {
		return ''
	}
	name := vue_static_property_name(t, prop) or { return '' }
	return if name in ['setup', 'render'] { name } else { '' }
}

// --- AST helpers ---

// vue_skip_ts_as ports skipTSAsExpression.
fn vue_skip_ts_as(t &estree.EsTree, node int) int {
	mut n := node
	for n >= 0 && t.typ(n) == .ts_as_expression {
		n = t.node(n, .expression) or { return n }
	}
	return n
}

// vue_skip_chain ports skipChainExpression.
fn vue_skip_chain(t &estree.EsTree, node int) int {
	mut n := node
	for n >= 0 && t.typ(n) == .chain_expression {
		n = t.node(n, .expression) or { return n }
	}
	return n
}

// vue_get_parent ports getParent: the parent, through `as` expressions.
fn vue_get_parent(t &estree.EsTree, node int) int {
	mut parent := t.nodes[node].parent
	for parent >= 0 && t.typ(parent) == .ts_as_expression {
		parent = t.nodes[parent].parent
	}
	return parent
}

// vue_is_string_literal ports isStringLiteral: a string Literal, or a TemplateLiteral without
// expressions.
fn vue_is_string_literal(t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .literal {
		return t.get(node, .value) is string
	}
	if t.typ(node) == .template_literal {
		return (t.list(node, .expressions) or { []int{} }).len == 0
	}
	return false
}

// vue_literal_string is String(value) of a Literal (`null` for null).
fn vue_literal_string(t &estree.EsTree, node int) string {
	v := t.get(node, .value)
	return match v {
		string {
			v
		}
		bool {
			v.str()
		}
		f64 {
			js_number_to_string(v)
		}
		estree.BigIntValue {
			v.digits
		}
		estree.RegExpValue {
			regex := t.prop(node, .regex) or { return 'null' }
			'/${regex.str}/${vue_canonical_regexp_flags(regex.str2)}'
		}
		else {
			'null'
		}
	}
}

// vue_canonical_regexp_flags is RegExp.prototype.flags: the flags in the order "dgimsuvy".
fn vue_canonical_regexp_flags(flags string) string {
	mut out := ''
	for f in 'dgimsuvy' {
		if flags.contains(f.ascii_str()) {
			out += f.ascii_str()
		}
	}
	return out
}

// vue_string_literal_value ports getStringLiteralValue.
fn vue_string_literal_value(t &estree.EsTree, node int, only_strings bool) ?string {
	if node < 0 {
		return none
	}
	if t.typ(node) == .literal {
		v := t.get(node, .value)
		if v is estree.Null || v is estree.Undefined {
			if only_strings {
				return none
			}
			return t.string_of(node, .bigint)
		}
		if v is string {
			return v
		}
		if only_strings {
			return none
		}
		return vue_literal_string(t, node)
	}
	if t.typ(node) == .template_literal {
		expressions := t.list(node, .expressions) or { []int{} }
		quasis := t.list(node, .quasis) or { []int{} }
		if expressions.len == 0 && quasis.len == 1 {
			v := t.get(quasis[0], .value)
			if v is estree.TemplateValue && v.has_cooked {
				return v.cooked
			}
		}
	}
	return none
}

// vue_static_property_name ports getStaticPropertyName of lib/utils (not ESLint's): of a
// Property, an AssignmentProperty, a MethodDefinition or a MemberExpression.
fn vue_static_property_name(t &estree.EsTree, node int) ?string {
	if node < 0 {
		return none
	}
	computed := t.flag(node, .computed) or { false }
	match t.typ(node) {
		.property, .method_definition {
			key := t.node(node, .key)?
			if !computed && t.typ(key) == .identifier {
				return t.string_of(key, .name)
			}
			return vue_string_literal_value(t, key, false)
		}
		.member_expression {
			property := t.node(node, .property)?
			if !computed {
				return if t.typ(property) == .identifier {
					t.string_of(property, .name)
				} else {
					none
				}
			}
			return vue_string_literal_value(t, property, false)
		}
		else {
			return none
		}
	}
}

// vue_is_property ports isProperty: a Property of an ObjectExpression.
fn vue_is_property(t &estree.EsTree, node int) bool {
	if t.typ(node) != .property {
		return false
	}
	parent := t.nodes[node].parent
	return parent < 0 || t.typ(parent) == .object_expression
}

// vue_find_property ports findProperty: the first Property of the object with that static name
// (and that `matching` accepts), -1 for none.
fn vue_find_property(t &estree.EsTree, object int, name string, matching ?fn (int) bool) int {
	for p in t.list(object, .properties) or { []int{} } {
		if !vue_is_property(t, p) || (vue_static_property_name(t, p) or { continue }) != name {
			continue
		}
		if f := matching {
			if !f(p) {
				continue
			}
		}
		return p
	}
	return -1
}

// vue_property_value is the `value` of a Property.
fn vue_property_value(t &estree.EsTree, property int) int {
	return t.node(property, .value) or { -1 }
}

// vue_is_this ports isThis: `this`, or a `const` initialized with `this`.
fn (mut c Checker) vue_is_this(root C.vt_node, t &estree.EsTree, node int) bool {
	if node < 0 {
		return false
	}
	if t.typ(node) == .this_expression {
		return true
	}
	if t.typ(node) != .identifier {
		return false
	}
	parent := t.nodes[node].parent
	if parent >= 0 {
		if t.typ(parent) == .member_expression && (t.node(parent, .property) or { -1 }) == node {
			return false
		}
		if t.typ(parent) == .property && (t.node(parent, .key) or { -1 }) == node
			&& !(t.flag(parent, .computed) or { false }) {
			return false
		}
	}
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return false
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	if defs.len != 1 {
		return false
	}
	def := defs[0]
	if def.kind != .variable || def.parent_kind != 'const' {
		return false
	}
	id := def.decl_id or { return false }
	if node_kind(id) != 'identifier' {
		return false
	}
	init := def.init or { return false }
	return node_kind(unwrap_parens(init)) == 'this'
}

// vue_find_variable is findVariable(getScope(node), node) of an Identifier: its variable, -1 for
// none.
fn (mut c Checker) vue_find_variable(root C.vt_node, t &estree.EsTree, node int) int {
	return c.unb_find_variable(root, t, node)
}

// vue_object_or_array ports getObjectOrArray: the object or array expression, or the one a
// `const` (with one definition) is initialized with; -1 for none.
fn (mut c Checker) vue_object_or_array(root C.vt_node, t &estree.EsTree, node int) int {
	if node < 0 {
		return -1
	}
	if t.typ(node) in [.object_expression, .array_expression] {
		return node
	}
	if t.typ(node) != .identifier {
		return -1
	}
	v := c.unb_find_variable(root, t, node)
	if v < 0 {
		return -1
	}
	tree := c.scope_tree(root)
	defs := tree.variables[v].defs
	if defs.len != 1 {
		return -1
	}
	def := defs[0]
	if def.kind != .variable || def.parent_kind != 'const' {
		return -1
	}
	id := def.decl_id or { return -1 }
	if node_kind(id) != 'identifier' {
		return -1
	}
	init := def.init or { return -1 }
	es_init := c.es_index_of(t, init) or { return -1 }
	return c.vue_object_or_array(root, t, es_init)
}

// --- the options of a component ---

// VuePropKind is the `type` of a ComponentProp or ComponentEmit.
enum VuePropKind as u8 {
	array      // an item of `props: ['a']`
	object     // a property of `props: { a: … }`
	type_      // a member of a type literal or interface of `defineProps<…>()`
	infer_type // a property of the type of `defineProps<…>()`, from the type checker
	unknown
}

// VueProp is a ComponentProp (or a ComponentEmit: `name` is then emitName): `node` is the node
// upstream reports (-1 for null), `key` the key (-1 for null), `value` the value of an object
// prop (skipTSAsExpression), -1 otherwise. A type prop's `types` and `required` (from
// inferRuntimeType) are not computed: no rule of this batch reads them.
struct VueProp {
	kind     VuePropKind
	has_name bool
	name     string
	node     int = -1
	key      int = -1
	value    int = -1
}

// vue_props_from_options ports getComponentPropsFromOptions.
fn vue_props_from_options(t &estree.EsTree, object int) []VueProp {
	props := vue_find_property(t, object, 'props', none)
	if props < 0 {
		return []
	}
	value := vue_property_value(t, props)
	if t.typ(value) !in [.object_expression, .array_expression] {
		return [VueProp{
			kind: .unknown
			node: value
		}]
	}
	return vue_props_from_define(t, value)
}

// vue_emits_from_options ports getComponentEmitsFromOptions.
fn vue_emits_from_options(t &estree.EsTree, object int) []VueProp {
	emits := vue_find_property(t, object, 'emits', none)
	if emits < 0 {
		return []
	}
	value := vue_property_value(t, emits)
	if t.typ(value) !in [.object_expression, .array_expression] {
		return [VueProp{
			kind: .unknown
			node: value
		}]
	}
	return vue_props_from_define(t, value)
}

// vue_props_from_define ports getComponentPropsFromDefine (and getComponentEmitsFromDefine,
// which is the same for emits).
fn vue_props_from_define(t &estree.EsTree, node int) []VueProp {
	mut out := []VueProp{}
	if t.typ(node) == .object_expression {
		for p in t.list(node, .properties) or { []int{} } {
			if !vue_is_property(t, p) {
				out << VueProp{
					kind: .unknown
					node: p
				}
				continue
			}
			value := vue_skip_ts_as(t, vue_property_value(t, p))
			if name := vue_static_property_name(t, p) {
				out << VueProp{
					kind:     .object
					has_name: true
					name:     name
					node:     p
					key:      t.node(p, .key) or { -1 }
					value:    value
				}
			} else {
				out << VueProp{
					kind:  .object
					node:  p
					value: value
				}
			}
		}
		return out
	}
	for e in t.list(node, .elements) or { []int{} } {
		if e < 0 {
			continue
		}
		if t.typ(e) in [.literal, .template_literal] {
			if name := vue_string_literal_value(t, e, false) {
				out << VueProp{
					kind:     .array
					has_name: true
					name:     name
					node:     e
					key:      e
				}
				continue
			}
		}
		out << VueProp{
			kind: .array
			node: e
		}
	}
	return out
}

// VuePropertyData is a ComponentPropertyData of iterateProperties: `kind` is .array or .object,
// `node` the reported node (the literal of an array item, the key of an object property) and
// `property` the Property of an object one.
struct VuePropertyData {
	kind     VuePropKind
	name     string
	group    string
	node     int
	property int = -1
}

// vue_iterate_properties ports iterateProperties: the names the groups (`props`, `computed`,
// `data`, `methods`, `setup`…) of the object define.
fn vue_iterate_properties(t &estree.EsTree, object int, groups []string) []VuePropertyData {
	mut out := []VuePropertyData{}
	for item in t.list(object, .properties) or { []int{} } {
		if t.typ(item) != .property {
			continue
		}
		name := vue_static_property_name(t, item) or { continue }
		if name == '' || name !in groups {
			continue
		}
		vue_iterate_property_value(t, vue_property_value(t, item), name, mut out)
	}
	return out
}

// vue_iterate_property_value ports iteratePropertyValue.
fn vue_iterate_property_value(t &estree.EsTree, value int, group string, mut out []VuePropertyData) {
	match t.typ(value) {
		.array_expression {
			for item in t.list(value, .elements) or { []int{} } {
				if item < 0 || t.typ(item) !in [.literal, .template_literal] {
					continue
				}
				name := vue_string_literal_value(t, item, false) or { continue }
				if name != '' {
					out << VuePropertyData{
						kind:  .array
						name:  name
						group: group
						node:  item
					}
				}
			}
		}
		.object_expression {
			vue_iterate_object_expression(t, value, group, mut out)
		}
		.function_expression, .arrow_function_expression {
			body := t.node(value, .body) or { return }
			if t.typ(body) == .block_statement {
				for item in t.list(body, .body) or { []int{} } {
					if t.typ(item) != .return_statement {
						continue
					}
					argument := t.node(item, .argument) or { continue }
					if t.typ(argument) == .object_expression {
						vue_iterate_object_expression(t, argument, group, mut out)
					}
				}
			} else if t.typ(value) == .arrow_function_expression && t.typ(body) == .object_expression {
				vue_iterate_object_expression(t, body, group, mut out)
			}
		}
		else {}
	}
}

// vue_iterate_object_expression ports iterateObjectExpression: a setter with a getter of the
// same name before or after it is left out (each getter pairs with one setter).
fn vue_iterate_object_expression(t &estree.EsTree, node int, group string, mut out []VuePropertyData) {
	properties := t.list(node, .properties) or { []int{} }
	mut used_getter := map[int]bool{}
	for item in properties {
		if t.typ(item) != .property {
			continue
		}
		key := t.node(item, .key) or { continue }
		if t.typ(key) !in [.identifier, .literal, .template_literal] {
			continue
		}
		name := vue_static_property_name(t, item) or { continue }
		if name == '' {
			continue
		}
		if (t.string_of(item, .kind) or { '' }) == 'set' {
			mut has_getter_pair := false
			for item2 in properties {
				if t.typ(item2) == .property && (t.string_of(item2, .kind) or { '' }) == 'get' {
					if used_getter[item2] {
						continue
					}
					if (vue_static_property_name(t, item2) or { continue }) == name {
						used_getter[item2] = true
						has_getter_pair = true
						break
					}
				}
			}
			if has_getter_pair {
				continue
			}
		}
		out << VuePropertyData{
			kind:     .object
			name:     name
			group:    group
			node:     key
			property: item
		}
	}
}

// vue_watch_handler_values ports iterateWatchHandlerValues: the handlers a watcher property (or
// its value) defines.
fn vue_watch_handler_values(t &estree.EsTree, node int, mut out []int) {
	value := if t.typ(node) == .property { vue_property_value(t, node) } else { node }
	if value < 0 {
		return
	}
	if t.typ(value) == .object_expression {
		handler := vue_find_property(t, value, 'handler', none)
		if handler >= 0 {
			out << vue_property_value(t, handler)
		}
	} else if t.typ(value) == .array_expression {
		for element in t.list(value, .elements) or { []int{} } {
			if element >= 0 && t.typ(element) != .spread_element {
				vue_watch_handler_values(t, element, mut out)
			}
		}
	} else {
		out << value
	}
}

// VueComputedProperty is a ComponentComputedProperty of getComputedProperties: its static name
// (has_key false for null) and the body of its getter (-1 for null).
struct VueComputedProperty {
	has_key bool
	key     string
	value   int = -1
}

// vue_computed_properties ports getComputedProperties.
fn vue_computed_properties(t &estree.EsTree, object int) []VueComputedProperty {
	computed := vue_find_property(t, object, 'computed', fn [t] (p int) bool {
		return t.typ(vue_property_value(t, p)) == .object_expression
	})
	if computed < 0 {
		return []
	}
	value := vue_property_value(t, computed)
	mut out := []VueComputedProperty{}
	for cp in t.list(value, .properties) or { []int{} } {
		if !vue_is_property(t, cp) {
			continue
		}
		key := vue_static_property_name(t, cp)
		prop_value := vue_skip_ts_as(t, vue_property_value(t, cp))
		mut body := -1
		if t.typ(prop_value) == .function_expression {
			body = t.node(prop_value, .body) or { -1 }
		} else if t.typ(prop_value) == .object_expression {
			get := vue_find_property(t, prop_value, 'get', fn [t] (p int) bool {
				return t.typ(vue_property_value(t, p)) == .function_expression
			})
			if get >= 0 {
				body = t.node(vue_property_value(t, get), .body) or { -1 }
			}
		}
		out << VueComputedProperty{
			has_key: key != none
			key:     key or { '' }
			value:   body
		}
	}
	return out
}

// vue_getter_body_from_computed_function ports getGetterBodyFromComputedFunction: the getter
// function of a `computed(…)` call, -1 for none.
fn vue_getter_body_from_computed_function(t &estree.EsTree, call int) int {
	args := t.list(call, .arguments) or { return -1 }
	if args.len == 0 {
		return -1
	}
	arg := args[0]
	if t.typ(arg) in [.function_expression, .arrow_function_expression] {
		return arg
	}
	if t.typ(arg) == .object_expression {
		get := vue_find_property(t, arg, 'get', fn [t] (p int) bool {
			return t.typ(vue_property_value(t, p)) in [.function_expression,
				.arrow_function_expression]
		})
		return if get >= 0 { vue_property_value(t, get) } else { -1 }
	}
	return -1
}

// vue_call_component_calls ports executeOnCallVueComponent: the calls `x.component(…)` with
// arguments whose `x` (through `as`) is an Identifier, in the order of their `component`
// identifiers.
fn vue_call_component_calls(t &estree.EsTree) []int {
	mut out := []int{}
	for node in 0 .. t.nodes.len {
		// "CallExpression > MemberExpression > Identifier[name='component']"
		if t.typ(node) != .identifier || (t.string_of(node, .name) or { '' }) != 'component' {
			continue
		}
		member := t.nodes[node].parent
		if member < 0 || t.typ(member) != .member_expression {
			continue
		}
		call := t.nodes[member].parent
		if call < 0 || t.typ(call) != .call_expression {
			continue
		}
		callee := t.node(call, .callee) or { continue }
		if t.typ(callee) != .member_expression {
			continue
		}
		object := vue_skip_ts_as(t, t.node(callee, .object) or { continue })
		args := t.list(call, .arguments) or { []int{} }
		if t.typ(object) == .identifier && (t.node(callee, .property) or { -1 }) == node
			&& args.len > 0 {
			out << call
		}
	}
	return out
}

// vue_has_invalid_eof ports hasInvalidEOF: the file has a template, and an `eof-*` parse error
// (templateBody.errors are those of the whole document).
fn (c &Checker) vue_has_invalid_eof() bool {
	if !c.is_vue() || c.vue.doc.template_body < 0 {
		return false
	}
	return c.vue.doc.errors.any(it.code.starts_with('eof-'))
}
