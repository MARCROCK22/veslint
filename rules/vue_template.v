module rules

import estree
import vue

// The template side of the vue/* rules: what eslint-plugin-vue 10.12.1's rules get from
// vue-eslint-parser's parser services (defineTemplateBodyVisitor, defineDocumentVisitor,
// getTemplateBodyTokenStore) and from lib/utils/index.ts, on the vue.Document of the .vue file
// being linted (c.vue.doc, set by set_vue). Every position is a byte offset of the file, as for the
// other rules; the line and column ESLint prints come from the document (doc.loc).
//
// How a template rule works:
//   - it returns [] at once unless c.vue_has_template() (a .vue file with a templateBody): for any
//     other file, defineTemplateBodyVisitor gives no listener, and veslint does no work;
//   - it walks the template with c.vue_template_steps() (the enter and leave events of
//     defineTemplateBodyVisitor's traversal, in its order and with its keys) or, when it only needs
//     the V* nodes on entering them, c.vue_template_vnodes();
//   - it reads the nodes with c.vue.doc.nodes[i] and the helpers below (directives, attributes,
//     element kinds), the tokens with the vue_tokens_* functions (vue_tokens.v);
//   - it reports with c.vue_report(start, end, message_id, data) (or a Finding of its own, the place
//     a position_range of the file), with a Fix in file bytes when it fixes.

// VueTKind is what a VueTNode is.
pub enum VueTKind as u8 {
	vnode         // a V* node: Document.nodes[v]
	estree        // a node of the ESTree of a snippet: Document.snippets[snippet].es.nodes[es]
	filter_callee // the Identifier vue-eslint-parser makes for the callee of the VFilter `v`
}

// VueTNode is a node of the template, as a listener of defineTemplateBodyVisitor gets it.
pub struct VueTNode {
pub:
	kind    VueTKind
	v       int = -1
	snippet int = -1
	es      int = -1
}

// VueStep is one event of the traversal of the template: entering or leaving a node.
pub struct VueStep {
pub:
	node  VueTNode
	leave bool
}

// vue_has_template: the file is a .vue file with a templateBody, the only case in which
// defineTemplateBodyVisitor's listeners run.
fn (c &Checker) vue_has_template() bool {
	return c.is_vue() && c.vue.doc.template_body >= 0
}

// vue_template_steps are the events of vue-eslint-parser's traversal of templateBody
// (src/ast/traverse.ts with its KEYS): depth first, the children of a V* node by its keys, those
// of an ESTree node by the keys of eslint-visitor-keys (no TypeScript child keys: a type argument
// in a template is not visited) and those of a TS* node by its own keys in the order
// typescript-estree creates them. Built once per file.
fn (mut c Checker) vue_template_steps() []VueStep {
	if !c.vue_has_template() {
		return []
	}
	if !c.vue.has_steps {
		c.vue.steps = vue_steps_from(c.vue.doc, VueTNode{
			kind: .vnode
			v:    c.vue.doc.template_body
		})
		c.vue.has_steps = true
	}
	return c.vue.steps
}

// vue_document_steps are the events of defineDocumentVisitor's traversal: the whole
// VDocumentFragment.
fn (c &Checker) vue_document_steps() []VueStep {
	if !c.is_vue() {
		return []
	}
	return vue_steps_from(c.vue.doc, VueTNode{
		kind: .vnode
		v:    0
	})
}

// vue_template_vnodes are the V* nodes of the template in the order the traversal enters them.
fn (mut c Checker) vue_template_vnodes() []int {
	if !c.vue_has_template() {
		return []
	}
	if !c.vue.has_vnodes {
		mut out := []int{}
		for step in c.vue_template_steps() {
			if !step.leave && step.node.kind == .vnode {
				out << step.node.v
			}
		}
		c.vue.vnodes = out
		c.vue.has_vnodes = true
	}
	return c.vue.vnodes
}

// vue_steps_from walks the template from `root`, with a stack (a template may nest deeply).
fn vue_steps_from(doc &vue.Document, root VueTNode) []VueStep {
	mut out := []VueStep{cap: doc.nodes.len * 2}
	mut stack := [VueStep{root, false}]
	for stack.len > 0 {
		top := stack.pop()
		out << top
		if top.leave {
			continue
		}
		stack << VueStep{top.node, true}
		kids := vue_tnode_children(doc, top.node)
		for k := kids.len - 1; k >= 0; k-- {
			stack << VueStep{kids[k], false}
		}
	}
	return out
}

fn vue_vnode(v int) VueTNode {
	return VueTNode{
		kind: .vnode
		v:    v
	}
}

// vue_expr_node is the template node of an Expr (none for a null one).
fn vue_expr_node(e vue.Expr) ?VueTNode {
	return match e.kind {
		.null { none }
		.vnode { vue_vnode(e.node) }
		.estree {
			VueTNode{
				kind:    .estree
				snippet: e.snippet
				es:      e.node
			}
		}
	}
}

// vue_tnode_children are the children of a template node in traversal order.
fn vue_tnode_children(doc &vue.Document, n VueTNode) []VueTNode {
	mut out := []VueTNode{}
	match n.kind {
		.filter_callee {}
		.estree {
			es := &doc.snippets[n.snippet].es
			for child in vue_es_children(es, n.es) {
				out << VueTNode{
					kind:    .estree
					snippet: n.snippet
					es:      child
				}
			}
		}
		.vnode {
			node := &doc.nodes[n.v]
			match node.typ {
				.v_document_fragment {
					for ch in node.children {
						out << vue_vnode(ch)
					}
				}
				.v_element {
					if node.start_tag >= 0 {
						out << vue_vnode(node.start_tag)
					}
					for ch in node.children {
						out << vue_vnode(ch)
					}
					if node.end_tag >= 0 {
						out << vue_vnode(node.end_tag)
					}
				}
				.v_start_tag {
					for a in node.attributes {
						out << vue_vnode(a)
					}
				}
				.v_attribute {
					if node.key >= 0 {
						out << vue_vnode(node.key)
					}
					if node.value >= 0 {
						out << vue_vnode(node.value)
					}
				}
				.v_directive_key {
					if node.dir_name >= 0 {
						out << vue_vnode(node.dir_name)
					}
					if node.argument >= 0 {
						out << vue_vnode(node.argument)
					}
					for m in node.modifiers {
						out << vue_vnode(m)
					}
				}
				.v_expression_container {
					if e := vue_expr_node(node.expression) {
						out << e
					}
				}
				.v_filter_sequence_expression {
					if e := vue_expr_node(node.expression) {
						out << e
					}
					for f in node.filters {
						out << vue_vnode(f)
					}
				}
				.v_filter {
					out << VueTNode{
						kind: .filter_callee
						v:    n.v
					}
					for e in node.exprs {
						if x := vue_expr_node(e) {
							out << x
						}
					}
				}
				.v_for_expression {
					for e in node.exprs {
						if x := vue_expr_node(e) {
							out << x
						}
					}
					if e := vue_expr_node(node.right) {
						out << e
					}
				}
				.v_on_expression, .v_slot_scope_expression, .v_generic_expression {
					for e in node.exprs {
						if x := vue_expr_node(e) {
							out << x
						}
					}
				}
				else {}
			}
		}
	}
	return out
}

// The keys of typescript-estree's visitor keys that eslint-visitor-keys 5 does not have: the
// template traversal does not enter them (on ESTree types).
const vue_ts_only_keys = ['typeArguments', 'typeParameters', 'typeAnnotation', 'returnType',
	'superTypeArguments', 'implements', 'decorators']

// vue_es_children are the children of an ESTree node of a template expression in the order of
// vue-eslint-parser's traversal: an ESTree type by the keys of eslint-visitor-keys; a TS* type
// (not in KEYS) by getFallbackKeys, its own properties in the order typescript-estree creates
// them, which is alphabetical.
fn vue_es_children(es &estree.EsTree, i int) []int {
	typ := es.nodes[i].typ
	mut out := []int{}
	if typ.type_name().starts_with('TS') {
		mut props := es.nodes[i].props.filter(it.kind in [.node, .list])
		props.sort(a.key.key_name() < b.key.key_name())
		for p in props {
			if p.kind == .node {
				out << p.idx
			} else {
				for item in es.lists[p.idx] {
					if item >= 0 {
						out << item
					}
				}
			}
		}
		return out
	}
	for key in estree.keys_of(typ) {
		if key.key_name() in vue_ts_only_keys {
			continue
		}
		p := es.prop(i, key) or { continue }
		match p.kind {
			.node {
				out << p.idx
			}
			.list {
				for item in es.lists[p.idx] {
					if item >= 0 {
						out << item
					}
				}
			}
			else {}
		}
	}
	return out
}

// vue_vnode_range is the range of a V* node as its `loc` gives it (a VOnExpression without
// statements takes its loc from other places than its range).
fn (c &Checker) vue_vnode_range(i int) (int, int) {
	n := &c.vue.doc.nodes[i]
	start := if n.loc_start >= 0 { n.loc_start } else { n.start }
	end := if n.loc_end >= 0 { n.loc_end } else { n.end }
	return start, end
}

// vue_tnode_range is the range of a template node (file bytes).
fn (c &Checker) vue_tnode_range(n VueTNode) (int, int) {
	return match n.kind {
		.vnode {
			c.vue_vnode_range(n.v)
		}
		.estree {
			node := c.vue.doc.snippets[n.snippet].es.nodes[n.es]
			node.start, node.end
		}
		.filter_callee {
			node := c.vue.doc.nodes[n.v]
			node.callee_start, node.callee_end
		}
	}
}

// vue_report is a report on the range [start, end) of the file.
fn (c &Checker) vue_report(start int, end int, message_id string, data map[string]string) Finding {
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       data
	}
}

// vue_report_vnode is a report on a V* node (`node: n` or `loc: n.loc`).
fn (c &Checker) vue_report_vnode(i int, message_id string, data map[string]string) Finding {
	start, end := c.vue_vnode_range(i)
	return c.vue_report(start, end, message_id, data)
}

// vue_text is the source text of [start, end).
fn (c &Checker) vue_text(start int, end int) string {
	return c.vue.doc.src[start..end]
}

// vue_vnode_text is sourceCode.getText of a V* node (its range).
fn (c &Checker) vue_vnode_text(i int) string {
	n := &c.vue.doc.nodes[i]
	return c.vue.doc.src[n.start..n.end]
}

// --- lib/utils/index.ts: elements, attributes and directives ---

// vue_directive_name is `key.name.name` of a directive (VAttribute with directive: true), '' for a
// plain attribute.
fn (c &Checker) vue_directive_name(attr int) string {
	a := &c.vue.doc.nodes[attr]
	if !a.directive || a.key < 0 {
		return ''
	}
	key := &c.vue.doc.nodes[a.key]
	return if key.dir_name >= 0 { c.vue.doc.nodes[key.dir_name].name } else { '' }
}

// vue_is_directive: the attribute is a directive named `name` (the selector
// `VAttribute[directive=true][key.name.name='<name>']`).
fn (c &Checker) vue_is_directive(attr int, name string) bool {
	a := &c.vue.doc.nodes[attr]
	return a.typ == .v_attribute && a.directive && c.vue_directive_name(attr) == name
}

// vue_directive_argument is the argument of a directive's key (-1 if none): a VIdentifier or a
// VExpressionContainer (a dynamic argument).
fn (c &Checker) vue_directive_argument(attr int) int {
	a := &c.vue.doc.nodes[attr]
	if !a.directive || a.key < 0 {
		return -1
	}
	return c.vue.doc.nodes[a.key].argument
}

// vue_static_argument is the name of the argument of a directive when it is a VIdentifier.
fn (c &Checker) vue_static_argument(attr int) ?string {
	arg := c.vue_directive_argument(attr)
	if arg < 0 || c.vue.doc.nodes[arg].typ != .v_identifier {
		return none
	}
	return c.vue.doc.nodes[arg].name
}

// vue_directive_modifiers are the modifiers of a directive's key (VIdentifiers).
fn (c &Checker) vue_directive_modifiers(attr int) []int {
	a := &c.vue.doc.nodes[attr]
	if !a.directive || a.key < 0 {
		return []
	}
	return c.vue.doc.nodes[a.key].modifiers
}

// vue_attribute_name is `key.name` of a plain attribute ('' for a directive).
fn (c &Checker) vue_attribute_name(attr int) string {
	a := &c.vue.doc.nodes[attr]
	if a.directive || a.key < 0 {
		return ''
	}
	return c.vue.doc.nodes[a.key].name
}

// vue_attributes are the attributes of an element (its start tag's).
fn (c &Checker) vue_attributes(element int) []int {
	el := &c.vue.doc.nodes[element]
	if el.start_tag < 0 {
		return []
	}
	return c.vue.doc.nodes[el.start_tag].attributes
}

// vue_get_attribute is getAttribute: the plain attribute named `name` (with that value, when given),
// or -1.
fn (c &Checker) vue_get_attribute(element int, name string, value ?string) int {
	for a in c.vue_attributes(element) {
		node := &c.vue.doc.nodes[a]
		if node.directive || c.vue.doc.nodes[node.key].name != name {
			continue
		}
		if v := value {
			if node.value < 0 || c.vue.doc.nodes[node.value].text != v {
				continue
			}
		}
		return a
	}
	return -1
}

// vue_has_attribute is hasAttribute.
fn (c &Checker) vue_has_attribute(element int, name string, value ?string) bool {
	return c.vue_get_attribute(element, name, value) >= 0
}

// vue_get_directives is getDirectives: the directives named `name`.
fn (c &Checker) vue_get_directives(element int, name string) []int {
	return c.vue_attributes(element).filter(c.vue_is_directive(it, name))
}

// vue_get_directive is getDirective: the first directive named `name` (with a static argument
// `argument`, when given), or -1.
fn (c &Checker) vue_get_directive(element int, name string, argument ?string) int {
	for a in c.vue_attributes(element) {
		if !c.vue_is_directive(a, name) {
			continue
		}
		if want := argument {
			got := c.vue_static_argument(a) or { continue }
			if got != want {
				continue
			}
		}
		return a
	}
	return -1
}

// vue_has_directive is hasDirective.
fn (c &Checker) vue_has_directive(element int, name string, argument ?string) bool {
	return c.vue_get_directive(element, name, argument) >= 0
}

// vue_is_vbind_same_name_shorthand is isVBindSameNameShorthand: `:foo` without a value, whose
// value vue-eslint-parser makes from the argument.
fn (c &Checker) vue_is_vbind_same_name_shorthand(attr int) bool {
	a := &c.vue.doc.nodes[attr]
	if !a.directive || c.vue_directive_name(attr) != 'bind' || a.value < 0 {
		return false
	}
	value := &c.vue.doc.nodes[a.value]
	if value.expression.kind != .estree {
		return false
	}
	es := &c.vue.doc.snippets[value.expression.snippet].es
	if es.nodes[value.expression.node].typ.type_name() != 'Identifier' {
		return false
	}
	key := &c.vue.doc.nodes[a.key]
	return key.start <= value.start && value.end <= key.end
}

// vue_expression is the expression of a VExpressionContainer (-1 when null), and whether it is an
// ESTree node (else a V* node: VOnExpression, VForExpression…).
fn (c &Checker) vue_container_expression(container int) vue.Expr {
	if container < 0 {
		return vue.no_expr
	}
	return c.vue.doc.nodes[container].expression
}

// vue_expr_type is the `type` of an Expr ('' when null).
fn (c &Checker) vue_expr_type(e vue.Expr) string {
	return match e.kind {
		.null { '' }
		.vnode { c.vue.doc.nodes[e.node].typ.type_name() }
		.estree { c.vue.doc.snippets[e.snippet].es.nodes[e.node].typ.type_name() }
	}
}

// vue_expr_range is the range of an Expr (file bytes).
fn (c &Checker) vue_expr_range(e vue.Expr) (int, int) {
	return match e.kind {
		.null {
			-1, -1
		}
		.vnode {
			c.vue_vnode_range(e.node)
		}
		.estree {
			n := c.vue.doc.snippets[e.snippet].es.nodes[e.node]
			n.start, n.end
		}
	}
}

// vue_is_empty_value_directive is isEmptyValueDirective: the directive has a value without an
// expression whose text is empty, quotes aside (`v-if=""`).
fn (c &Checker) vue_is_empty_value_directive(attr int) bool {
	a := &c.vue.doc.nodes[attr]
	if a.value < 0 || !c.vue.doc.nodes[a.value].expression.is_null() {
		return false
	}
	mut text := c.vue_vnode_text(a.value)
	if text.len > 0 && (text[0] == `"` || text[0] == `'`) && text[0] == text[text.len - 1] {
		// `'x'.slice(1, -1)`: a single quote character gives ''.
		text = if text.len >= 2 { text[1..text.len - 1] } else { '' }
	}
	return text == ''
}

// vue_is_empty_expression_value_directive is isEmptyExpressionValueDirective: the directive has a
// value without an expression and the value has no token but its quotes (`=" "`, `="/* */"`).
fn (c &Checker) vue_is_empty_expression_value_directive(attr int) bool {
	a := &c.vue.doc.nodes[attr]
	if a.value < 0 || !c.vue.doc.nodes[a.value].expression.is_null() {
		return false
	}
	value := &c.vue.doc.nodes[a.value]
	mut quote1 := ''
	mut has_quote2 := false
	for token in c.vue_tokens_in(a.start, a.end) {
		if token.end <= value.start {
			continue
		}
		if value.end <= token.start {
			return true
		}
		if quote1 == '' && token.typ == 'Punctuator' && token.value in ['"', "'"] {
			quote1 = token.value
			continue
		}
		if !has_quote2 && quote1 != '' && token.typ == 'Punctuator' && token.value == quote1 {
			has_quote2 = true
			continue
		}
		return false
	}
	return true
}

// vue_prev_sibling is prevSibling: the element before `element` among its parent's children.
fn (c &Checker) vue_prev_sibling(element int) int {
	parent := c.vue.doc.nodes[element].parent
	if parent < 0 {
		return -1
	}
	mut prev := -1
	for sibling in c.vue.doc.nodes[parent].children {
		if sibling == element {
			return prev
		}
		if c.vue.doc.nodes[sibling].typ == .v_element {
			prev = sibling
		}
	}
	return -1
}

// vue_prev_element_has_if is prevElementHasIf: the previous sibling element has a v-if or a
// v-else-if.
fn (c &Checker) vue_prev_element_has_if(element int) bool {
	prev := c.vue_prev_sibling(element)
	if prev < 0 {
		return false
	}
	for a in c.vue_attributes(prev) {
		name := c.vue_directive_name(a)
		if c.vue.doc.nodes[a].directive && (name == 'if' || name == 'else-if') {
			return true
		}
	}
	return false
}

// vue_is_custom_component is isCustomComponent: the element has `is`, `:is` or `v-is`, or its
// rawName is not a well-known element name of its namespace (of any, with
// `ignore_element_namespaces`).
fn (c &Checker) vue_is_custom_component(element int, ignore_element_namespaces bool) bool {
	if c.vue_has_attribute(element, 'is', none) || c.vue_has_directive(element, 'bind', 'is')
		|| c.vue_has_directive(element, 'is', none) {
		return true
	}
	el := &c.vue.doc.nodes[element]
	is_html := vue_is_html_well_known_element_name(el.raw_name)
	is_svg := vue_is_svg_well_known_element_name(el.raw_name)
	is_math := vue_is_math_well_known_element_name(el.raw_name)
	if ignore_element_namespaces {
		return !is_html && !is_svg && !is_math
	}
	return (el.namespace == .html && !is_html) || (el.namespace == .svg && !is_svg)
		|| (el.namespace == .mathml && !is_math)
}

// vue_is_html_element_node is isHtmlElementNode.
fn (c &Checker) vue_is_html_element_node(element int) bool {
	return c.vue.doc.nodes[element].namespace == .html
}

fn vue_is_html_well_known_element_name(name string) bool {
	return name in vue_html_element_names
}

fn vue_is_svg_well_known_element_name(name string) bool {
	return name in vue_svg_element_names
}

fn vue_is_math_well_known_element_name(name string) bool {
	return name in vue_math_element_names
}

fn vue_is_html_void_element_name(name string) bool {
	return name in vue_void_element_names
}

// vue_element_of is the element a node is in: the nearest VElement among its ancestors (itself
// included).
fn (c &Checker) vue_element_of(i int) int {
	mut n := i
	for n >= 0 {
		if c.vue.doc.nodes[n].typ == .v_element {
			return n
		}
		n = c.vue.doc.nodes[n].parent
	}
	return -1
}

// vue_attribute_element is the element of an attribute (attribute -> start tag -> element).
fn (c &Checker) vue_attribute_element(attr int) int {
	start_tag := c.vue.doc.nodes[attr].parent
	return if start_tag < 0 { -1 } else { c.vue.doc.nodes[start_tag].parent }
}
