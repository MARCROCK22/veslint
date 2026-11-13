module rules

import time
import treesitter { named_children, node_field, node_kind, node_parent, position_of }

// Port of the `no-unused-private-class-members` rule of typescript-eslint 8.62.0 (it has no
// options), with the class scope analyzer it is built on (util/class-scope-analyzer): a visitor of
// the whole program that keeps a stack of `this` scopes (a class, or a function, a method or a
// static block that rebinds `this`) and counts the reads and writes of the members of each class
// through `this`, the class name, a `const self = this`, a parameter typed as the class, `#name`
// and destructuring from `this`.

const nupcm_messages = {
	'unusedPrivateClassMember': "Private class member '{{classMemberName}}' is defined but never used."
}

// NupcmMember is a member of a class (Member): its name as written, the node reported, and its
// reads and writes.
struct NupcmMember {
	name        string
	name_node   C.TSNode
	is_private  bool // `private`
	is_hash     bool // `#name`
	is_accessor bool // a getter, a setter or an `accessor`
mut:
	reads  int
	writes int
}

// NupcmClass is a ClassScope: its name and its members by key (a later member with the same key
// replaces the earlier one, as Map.set does).
struct NupcmClass {
	name     string
	has_name bool
mut:
	instance map[string]int
	statics  map[string]int
}

// NupcmScope is a `this` scope: a class (class_index >= 0) or an IntermediateScope.
// `this_context` is the class `this` refers to (-1 for none) and `is_static` tells whether it is
// the class itself rather than an instance.
struct NupcmScope {
	upper        int
	class_index  int
	this_context int
	is_static    bool
}

struct NupcmAnalyzer {
mut:
	scopes  []NupcmScope
	classes []NupcmClass
	members []NupcmMember
}

const nupcm_class_kinds = ['class_declaration', 'abstract_class_declaration', 'class']

fn (mut c Checker) lint_no_unused_private_class_members(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	tree := c.scope_tree(root)
	// analyzeClassMemberUsage: the Program is an IntermediateScope without `this`.
	mut a := NupcmAnalyzer{}
	a.scopes << NupcmScope{
		upper:        -1
		class_index:  -1
		this_context: -1
	}
	c.nupcm_visit(mut a, tree, root, 0)
	for class in a.classes {
		for _, index in class.instance {
			c.nupcm_report(a.members[index], mut findings)
		}
		for _, index in class.statics {
			c.nupcm_report(a.members[index], mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += a.members.len
	return findings
}

// nupcm_report reports a private member that is not used: never read, and, if it is an accessor
// (which may have side effects), never written either.
fn (c &Checker) nupcm_report(m NupcmMember, mut findings []Finding) {
	if (!m.is_private && !m.is_hash) || m.reads > 0 || (m.writes > 0 && m.is_accessor) {
		return
	}
	findings << Finding{
		stmt:       c.es_binding_position(m.name_node)
		message_id: 'unusedPrivateClassMember'
		data:       {
			'classMemberName': m.name
		}
	}
}

// nupcm_visit visits a node in the `this` scope `scope`, like the Visitor of the analyzer: the
// handlers of ClassDeclaration and ClassExpression, FunctionDeclaration, FunctionExpression and
// StaticBlock (new scopes), MemberExpression, PrivateIdentifier, VariableDeclarator,
// AssignmentExpression and AssignmentPattern; everything else visits its children.
fn (mut c Checker) nupcm_visit(mut a NupcmAnalyzer, tree &ScopeTree, n C.TSNode, scope int) {
	kind := node_kind(n)
	match kind {
		'class_declaration', 'abstract_class_declaration', 'class' {
			c.nupcm_visit_class(mut a, tree, n, []C.TSNode{}, scope)
		}
		'export_statement' {
			// `@dec export class C {}`: the decorators belong to the class.
			decorators := named_children(n).filter(node_kind(it) == 'decorator')
			if decorators.len > 0 {
				if declaration := node_field(n, 'declaration') {
					if node_kind(declaration) in nupcm_class_kinds {
						c.nupcm_visit_class(mut a, tree, declaration, decorators, scope)
						return
					}
				}
			}
			c.nupcm_visit_children(mut a, tree, n, scope)
		}
		'function_declaration', 'generator_function_declaration', 'function_expression',
		'generator_function' {
			inner := c.nupcm_intermediate(mut a, n, scope)
			c.nupcm_visit_children(mut a, tree, n, inner)
		}
		'method_definition', 'method_signature', 'abstract_method_signature' {
			c.nupcm_visit_method(mut a, tree, n, scope)
		}
		'class_static_block' {
			// A static block: `this` is the class.
			inner := a.scopes.len
			a.scopes << NupcmScope{
				upper:        scope
				class_index:  -1
				this_context: a.scopes[scope].class_index
				is_static:    true
			}
			c.nupcm_visit_children(mut a, tree, n, inner)
		}
		'public_field_definition' {
			c.nupcm_visit_field(mut a, tree, n, scope)
		}
		'member_expression', 'subscript_expression' {
			c.nupcm_visit_children(mut a, tree, n, scope)
			c.nupcm_member_expression(mut a, tree, n, scope)
		}
		'private_property_identifier' {
			parent := node_parent(n) or { return }
			c.nupcm_private_name(mut a, n, parent, scope)
		}
		'variable_declarator' {
			// `const { x } = this`
			c.nupcm_visit_children(mut a, tree, n, scope)
			c.nupcm_this_destructuring(mut a, n, 'name', 'value', scope)
		}
		'assignment_expression', 'assignment_pattern' {
			// `({ x } = this)`, `[{ x } = this] = list`
			c.nupcm_visit_children(mut a, tree, n, scope)
			c.nupcm_this_destructuring(mut a, n, 'left', 'right', scope)
		}
		'required_parameter' {
			// A parameter with a default value is an AssignmentPattern: `({ x } = this) => {}`.
			c.nupcm_visit_children(mut a, tree, n, scope)
			c.nupcm_this_destructuring(mut a, n, 'pattern', 'value', scope)
		}
		'type_query' {
			// `typeof a.b` is a TSQualifiedName, not a MemberExpression.
		}
		else {
			c.nupcm_visit_children(mut a, tree, n, scope)
		}
	}
}

fn (mut c Checker) nupcm_visit_children(mut a NupcmAnalyzer, tree &ScopeTree, n C.TSNode, scope int) {
	for child in named_children(n) {
		c.nupcm_visit(mut a, tree, child, scope)
	}
}

// nupcm_visit_class ports visitClass and the constructor of ClassScope: the members of the class,
// then its children in its own scope.
fn (mut c Checker) nupcm_visit_class(mut a NupcmAnalyzer, tree &ScopeTree, n C.TSNode, outer_decorators []C.TSNode, scope int) {
	index := a.classes.len
	mut class := NupcmClass{}
	if name := node_field(n, 'name') {
		class = NupcmClass{
			name:     c.identifier_name(name)
			has_name: true
		}
	}
	a.classes << class
	inner := a.scopes.len
	a.scopes << NupcmScope{
		upper:        scope
		class_index:  index
		this_context: index
	}
	if body := node_field(n, 'body') {
		c.nupcm_collect_members(mut a, index, body)
	}
	for decorator in outer_decorators {
		c.nupcm_visit(mut a, tree, decorator, inner)
	}
	c.nupcm_visit_children(mut a, tree, n, inner)
}

// nupcm_collect_members ports the members of ClassScope: the parameter properties of the
// constructor, the methods, accessors and fields (abstract or not) with a name that is not
// computed (or a literal); not the static blocks nor the index signatures.
fn (mut c Checker) nupcm_collect_members(mut a NupcmAnalyzer, class int, body C.TSNode) {
	for member in named_children(body) {
		kind := node_kind(member)
		if kind !in ['method_definition', 'method_signature', 'abstract_method_signature',
			'public_field_definition'] {
			continue
		}
		if kind != 'public_field_definition' && kind != 'abstract_method_signature'
			&& c.pfa_is_constructor(member) {
			parameters := node_field(member, 'parameters') or { continue }
			for parameter in named_children(parameters) {
				c.nupcm_add_parameter_property(mut a, class, parameter)
			}
			continue
		}
		key := node_field(member, 'name') or { continue }
		name, code_name, name_node := c.nupcm_member_name(key) or { continue }
		accessibility := children_of_kind(member, 'accessibility_modifier')
		index := a.members.len
		a.members << NupcmMember{
			name:        code_name
			name_node:   name_node
			is_private:  accessibility.len > 0 && c.text(accessibility[0]) == 'private'
			is_hash:     node_kind(key) == 'private_property_identifier'
			is_accessor: if kind == 'public_field_definition' {
				children_of_kind(member, 'accessor').len > 0
			} else {
				children_of_kind(member, 'get').len > 0 || children_of_kind(member, 'set').len > 0
			}
		}
		if children_of_kind(member, 'static').len > 0 {
			a.classes[class].statics[name] = index
		} else {
			a.classes[class].instance[name] = index
		}
	}
}

// nupcm_add_parameter_property adds a TSParameterProperty (a parameter of the constructor with a
// modifier) as an instance member.
fn (mut c Checker) nupcm_add_parameter_property(mut a NupcmAnalyzer, class int, parameter C.TSNode) {
	if node_kind(parameter) !in ['required_parameter', 'optional_parameter'] {
		return
	}
	accessibility := children_of_kind(parameter, 'accessibility_modifier')
	if accessibility.len == 0 && children_of_kind(parameter, 'override_modifier').len == 0
		&& children_of_kind(parameter, 'readonly').len == 0 {
		return
	}
	pattern := node_field(parameter, 'pattern') or { return }
	if node_kind(pattern) != 'identifier' {
		return
	}
	name := c.identifier_name(pattern)
	a.classes[class].instance[name] = a.members.len
	a.members << NupcmMember{
		name:       name
		name_node:  pattern
		is_private: accessibility.len > 0 && c.text(accessibility[0]) == 'private'
	}
}

// nupcm_member_name ports extractNameForMember: the key, the name as written and the node of a
// member name; none for a computed name that is not a literal.
fn (c &Checker) nupcm_member_name(key C.TSNode) ?(string, string, C.TSNode) {
	match node_kind(key) {
		'computed_property_name' {
			inner := unwrap_parens(first_named(key)?)
			name := c.nupcm_computed_name(inner)?
			return name, name, inner
		}
		'string', 'number' {
			name := c.nupcm_computed_name(key)?
			return name, name, key
		}
		'private_property_identifier' {
			name := c.identifier_name(key)
			return '#private@@${name}', name, key
		}
		else {
			name := c.identifier_name(key)
			return name, name, key
		}
	}
}

// nupcm_computed_name ports extractComputedName: `String(value)` of a literal ('null' for
// `null`), or the raw text of a template without substitutions.
fn (c &Checker) nupcm_computed_name(n C.TSNode) ?string {
	match node_kind(n) {
		'template_string' {
			if named_children(n).any(node_kind(it) == 'template_substitution') {
				return none
			}
			text := c.text(n)
			return text[1..text.len - 1]
		}
		'string', 'number', 'true', 'false', 'null', 'regex' {
			return c.literal_name(n)
		}
		else {
			return none
		}
	}
}

// nupcm_intermediate creates the IntermediateScope of a function: `this` is the class for a class
// method; for a function whose first parameter is `this: C`, the closest enclosing class named
// C; otherwise there is none.
fn (mut c Checker) nupcm_intermediate(mut a NupcmAnalyzer, n C.TSNode, upper int) int {
	mut this_context := -1
	mut is_static := false
	parent := node_parent(n) or { n }
	if node_kind(n) == 'method_definition' && node_kind(parent) == 'class_body' {
		this_context = a.scopes[upper].class_index
		is_static = children_of_kind(n, 'static').len > 0
	} else if parameters := node_field(n, 'parameters') {
		list := named_children(parameters)
		if list.len > 0 {
			if pattern := node_field(list[0], 'pattern') {
				if node_kind(pattern) == 'this' {
					if name := nupcm_annotation_reference(list[0]) {
						this_context = c.nupcm_class_named(a, upper, c.identifier_name(name))
					}
				}
			}
		}
	}
	index := a.scopes.len
	a.scopes << NupcmScope{
		upper:        upper
		class_index:  -1
		this_context: this_context
		is_static:    is_static
	}
	return index
}

// nupcm_annotation_reference is the name of the type annotation of a parameter when it is a
// TSTypeReference whose name is an Identifier (`x: C` or `x: C<T>`).
fn nupcm_annotation_reference(parameter C.TSNode) ?C.TSNode {
	annotation := node_field(parameter, 'type')?
	t := unwrap_type_parens(first_named(annotation)?)
	match node_kind(t) {
		'type_identifier' {
			return t
		}
		'generic_type' {
			name := node_field(t, 'name')?
			if node_kind(name) == 'type_identifier' {
				return name
			}
		}
		else {}
	}
	return none
}

// nupcm_visit_method visits a method: its name (a computed one) belongs to the MethodDefinition or
// Property, the rest to its FunctionExpression, which is an IntermediateScope; the overloads
// (TSEmptyBodyFunctionExpression) and abstract methods have none. The `#name` of a class method is
// its definition, not a use; the one of an abstract method is visited.
fn (mut c Checker) nupcm_visit_method(mut a NupcmAnalyzer, tree &ScopeTree, n C.TSNode, scope int) {
	key := node_field(n, 'name') or { n }
	if node_kind(key) == 'computed_property_name' {
		c.nupcm_visit_children(mut a, tree, key, scope)
	} else if node_kind(key) == 'private_property_identifier'
		&& node_kind(n) == 'abstract_method_signature' {
		c.nupcm_private_name(mut a, key, n, scope)
	}
	inner := if node_kind(n) == 'method_definition' {
		c.nupcm_intermediate(mut a, n, scope)
	} else {
		scope
	}
	for child in named_children(n) {
		if node_key(child) == node_key(key) && node_kind(child) == node_kind(key) {
			continue
		}
		// A decorator of a parameter is part of the function; tree-sitter puts the decorators of
		// the method itself before it, in the class body.
		c.nupcm_visit(mut a, tree, child, inner)
	}
}

// nupcm_visit_field visits a PropertyDefinition, an AccessorProperty or an abstract one. A
// function expression that is the value of a PropertyDefinition is an IntermediateScope whose
// `this` is the class; the `#name` of a PropertyDefinition is its definition, and the one of the
// others is visited as a use.
fn (mut c Checker) nupcm_visit_field(mut a NupcmAnalyzer, tree &ScopeTree, n C.TSNode, scope int) {
	is_property := children_of_kind(n, 'accessor').len == 0
		&& children_of_kind(n, 'abstract').len == 0
	key := node_field(n, 'name') or { n }
	mut value_key := u64(0)
	if value := node_field(n, 'value') {
		value_key = node_key(value)
	}
	for child in named_children(n) {
		if node_key(child) == node_key(key) && node_kind(child) == node_kind(key) {
			if node_kind(key) == 'computed_property_name' {
				c.nupcm_visit_children(mut a, tree, key, scope)
			} else if node_kind(key) == 'private_property_identifier' && !is_property {
				c.nupcm_private_name(mut a, key, n, scope)
			}
			continue
		}
		if node_key(child) == value_key {
			function := unwrap_parens(child)
			if is_property && node_kind(function) in ['function_expression', 'generator_function'] {
				inner := a.scopes.len
				a.scopes << NupcmScope{
					upper:        scope
					class_index:  -1
					this_context: a.scopes[scope].class_index
					is_static:    children_of_kind(n, 'static').len > 0
				}
				c.nupcm_visit_children(mut a, tree, function, inner)
				continue
			}
		}
		c.nupcm_visit(mut a, tree, child, scope)
	}
}

// nupcm_class_named ports findClassScopeWithName: the closest class scope with that name, from
// `scope` outwards.
fn (c &Checker) nupcm_class_named(a NupcmAnalyzer, scope int, name string) int {
	mut s := scope
	for s >= 0 {
		class := a.scopes[s].class_index
		if class >= 0 && a.classes[class].has_name && a.classes[class].name == name {
			return class
		}
		s = a.scopes[s].upper
	}
	return -1
}

// nupcm_private_name ports the PrivateIdentifier visitor: the member of that `#name` of the closest
// scope whose `this` has it (a class cannot have a static and an instance private member with the
// same name, and an inner class cannot reach a private member of an outer one it shadows).
fn (mut c Checker) nupcm_private_name(mut a NupcmAnalyzer, n C.TSNode, parent C.TSNode, scope int) {
	key := '#private@@${c.identifier_name(n)}'
	mut s := scope
	for s >= 0 {
		context := a.scopes[s].this_context
		if context >= 0 {
			index := a.classes[context].instance[key] or { a.classes[context].statics[key] or { -1 } }
			if index >= 0 {
				nupcm_count_reference(parent, mut a.members[index])
				return
			}
		}
		s = a.scopes[s].upper
	}
}

// nupcm_member_expression ports the MemberExpression visitor for a property that is not `#name`:
// the member of the class the object is (getObjectClass) with that name.
fn (mut c Checker) nupcm_member_expression(mut a NupcmAnalyzer, tree &ScopeTree, n C.TSNode, scope int) {
	property := member_property(n) or { return }
	if node_kind(property) == 'private_property_identifier' {
		return
	}
	name := if node_kind(n) == 'subscript_expression' {
		c.nupcm_computed_name(property) or { return }
	} else {
		c.identifier_name(property)
	}
	object := unwrap_parens(node_field(n, 'object') or { return })
	class, is_static := c.nupcm_object_class(a, tree, n, object, scope) or { return }
	index := if is_static {
		a.classes[class].statics[name] or { return }
	} else {
		a.classes[class].instance[name] or { return }
	}
	nupcm_count_reference(n, mut a.members[index])
}

// nupcm_object_class ports getObjectClass: `this`; the name of an enclosing class (static); a
// variable whose first definition is `const self = this` never written again; or a parameter
// typed `C` (instance) or `typeof C` (static), C an enclosing class.
fn (c &Checker) nupcm_object_class(a NupcmAnalyzer, tree &ScopeTree, member C.TSNode, object C.TSNode, scope int) ?(int, bool) {
	if node_kind(object) == 'this' {
		if a.scopes[scope].this_context < 0 {
			return none
		}
		return a.scopes[scope].this_context, a.scopes[scope].is_static
	}
	if estree_type(object) != 'Identifier' {
		return none
	}
	name := c.identifier_name(object)
	class := c.nupcm_class_named(a, scope, name)
	if class >= 0 {
		return class, true
	}
	variable := nupcm_find_variable(tree, member, name)
	if variable < 0 || tree.variables[variable].defs.len == 0 {
		return none
	}
	first := tree.variables[variable].defs[0]
	if first.kind == .variable {
		// A VariableDeclarator: `const self = this` (or `let`) that is not written again.
		init := first.init or { return none }
		if node_kind(unwrap_parens(init)) != 'this' {
			return none
		}
		for r in tree.variables[variable].references {
			if tree.references[r].write && !tree.references[r].init {
				return none
			}
		}
		if a.scopes[scope].this_context < 0 {
			return none
		}
		return a.scopes[scope].this_context, a.scopes[scope].is_static
	}
	// The type annotation of the name of the definition: a parameter or a catch clause.
	holder := node_parent(first.name) or { return none }
	mut field := ''
	if node_kind(holder) in ['required_parameter', 'optional_parameter'] {
		field = 'pattern'
	} else if node_kind(holder) == 'catch_clause' {
		field = 'parameter'
	} else {
		return none
	}
	declared := node_field(holder, field) or { return none }
	if node_key(declared) != node_key(first.name) {
		return none
	}
	annotation := node_field(holder, 'type') or { return none }
	t := unwrap_type_parens(first_named(annotation) or { return none })
	if reference := nupcm_annotation_reference(holder) {
		class_index := c.nupcm_class_named(a, scope, c.identifier_name(reference))
		if class_index >= 0 {
			return class_index, false
		}
		return none
	}
	if node_kind(t) == 'type_query' {
		mut expression := first_named(t) or { return none }
		if node_kind(expression) == 'instantiation_expression' {
			expression = first_named(expression) or { return none }
		}
		if node_kind(expression) == 'identifier' {
			class_index := c.nupcm_class_named(a, scope, c.identifier_name(expression))
			if class_index >= 0 {
				return class_index, true
			}
		}
	}
	return none
}

// nupcm_find_variable ports findVariableInScope: from the scope the closest node around
// `n` creates (ScopeManager#acquire, which takes the first scope of a node: the
// function-expression-name scope of a named function expression, the class field initializer
// scope of a field value), the first scope upwards that declares `name`.
fn nupcm_find_variable(t &ScopeTree, n C.TSNode, name string) int {
	mut s := nupcm_nearest_scope(t, n)
	for s >= 0 {
		if v := t.scopes[s].set[name] {
			return v
		}
		s = t.scopes[s].upper
	}
	return -1
}

// nupcm_nearest_scope ports findNearestScope: the first scope the node or its closest ancestor
// creates (a method's name and decorators are outside its function).
fn nupcm_nearest_scope(t &ScopeTree, n C.TSNode) int {
	mut node := n
	mut from := ?C.TSNode(none)
	for _ in 0 .. 100000 {
		if node_kind(node) == 'decorator' {
			if parent := node_parent(node) {
				if node_kind(parent) == 'export_statement' {
					if declaration := node_field(parent, 'declaration') {
						from = node
						node = declaration
						continue
					}
				}
			}
		}
		if scopes := t.by_block[scope_block_key(node)] {
			mut candidates := scopes.clone()
			if scope_is_method(node) && !scope_in_method_function(node, from) {
				candidates = candidates.filter(t.scopes[it].kind != .function)
			}
			if candidates.len > 0 {
				return candidates[0]
			}
		}
		from = node
		node = node_parent(node) or { break }
	}
	return 0
}

// nupcm_this_destructuring ports handleThisDestructuring: an object pattern assigned from `this`
// (`const { x } = this`) reads the members its keys name.
fn (mut c Checker) nupcm_this_destructuring(mut a NupcmAnalyzer, n C.TSNode, pattern_field string, value_field string, scope int) {
	pattern := node_field(n, pattern_field) or { return }
	value := node_field(n, value_field) or { return }
	if node_kind(pattern) != 'object_pattern' || node_kind(unwrap_parens(value)) != 'this' {
		return
	}
	context := a.scopes[scope].this_context
	if context < 0 {
		return
	}
	for property in named_children(pattern) {
		// Properties with an Identifier key that is not computed (not a rest element).
		key := match node_kind(property) {
			'shorthand_property_identifier_pattern' {
				property
			}
			'object_assignment_pattern' {
				left := node_field(property, 'left') or { continue }
				if node_kind(left) != 'shorthand_property_identifier_pattern' {
					continue
				}
				left
			}
			'pair_pattern' {
				node_field(property, 'key') or { continue }
			}
			else {
				continue
			}
		}
		if node_kind(key) !in ['property_identifier', 'shorthand_property_identifier_pattern'] {
			continue
		}
		name := c.identifier_name(key)
		index := if a.scopes[scope].is_static {
			a.classes[context].statics[name] or { continue }
		} else {
			a.classes[context].instance[name] or { continue }
		}
		// countReference(prop.key): the key is never the value of its Property (they are two
		// nodes even when shorthand), so it is a read.
		a.members[index].reads++
	}
}

// nupcm_es_parent is the ESTree parent of an expression (parentheses are not nodes); none for
// the outermost element of an optional chain, whose parent is its ChainExpression.
fn nupcm_es_parent(n C.TSNode) ?C.TSNode {
	if is_chain_element(n) && is_estree_chain_root(n) {
		return none
	}
	mut parent := node_parent(n)?
	for node_kind(parent) == 'parenthesized_expression' {
		parent = node_parent(parent)?
	}
	return parent
}

fn nupcm_field_is(parent C.TSNode, field string, child C.TSNode) bool {
	value := node_field(parent, field) or { return false }
	return node_key(unwrap_parens(value)) == node_key(child)
}

// nupcm_count_reference ports countReference: `node` (the member access, or the node that holds
// the `#name`) writes the member when it is the target of `=`, of a for-in/of, of a default value,
// of a compound assignment or an increment that is a statement of its own, or a target in an
// object pattern, a rest element or an array pattern; otherwise it reads it.
fn nupcm_count_reference(node C.TSNode, mut m NupcmMember) {
	grandparent := nupcm_es_parent(node) or {
		m.reads++
		return
	}
	match node_kind(grandparent) {
		'assignment_expression', 'augmented_assignment_expression' {
			if nupcm_field_is(grandparent, 'left', node) {
				if node_kind(grandparent) == 'assignment_expression' {
					m.writes++
					return
				}
				// `this.#x += 1;` writes it; `a = this.#x += 1` also reads it.
				statement := nupcm_es_parent(grandparent) or {
					m.reads++
					return
				}
				if node_kind(statement) == 'expression_statement' {
					m.writes++
				} else {
					m.reads++
				}
				return
			}
		}
		'for_in_statement', 'assignment_pattern' {
			if nupcm_field_is(grandparent, 'left', node) {
				m.writes++
				return
			}
		}
		else {}
	}
	match node_kind(grandparent) {
		'update_expression' {
			// `this.#x++;`
			if statement := nupcm_es_parent(grandparent) {
				if node_kind(statement) == 'expression_statement' {
					m.writes++
					return
				}
			}
		}
		'pair_pattern' {
			if nupcm_field_is(grandparent, 'value', node) {
				m.writes++
				return
			}
		}
		'rest_pattern', 'array_pattern' {
			m.writes++
			return
		}
		else {}
	}
	m.reads++
}
