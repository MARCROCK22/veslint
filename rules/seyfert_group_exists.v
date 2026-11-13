module rules

import os
import time
import tsgo { SymbolResponse, TypeResponse }
import treesitter { named_children, node_kind, node_start, position_of }

// Port of the `group-exists` rule of @slipher/eslint-plugin 1.1.0 (it has no options): the
// `@Group` of a subcommand of a class that extends seyfert's Command (listed in its `@Options`, or
// the default export of a file of its directory with `@AutoLoad`) names a group the `@Groups` or
// `@GroupsT` of the command and of its bases do not declare.

const sy_ge_messages = {
	'unknownGroup':         "Group `{{group}}` is not declared in this command's `@Groups`/`@GroupsT`."
	'unknownGroupAutoload': "Subcommand `{{sub}}` (`{{file}}`) uses group `{{group}}`, not declared in this command's `@Groups`/`@GroupsT`."
}

fn (mut c Checker) lint_seyfert_group_exists(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	classes, mut asked := c.sy_decorated_classes(root)
	for class in classes {
		for decorator in class.decorators {
			if argument := sy_first_argument(decorator) {
				asked << argument
				if node_kind(argument) == 'array' {
					asked << named_children(argument).filter(node_kind(it) != 'spread_element')
				}
			}
		}
	}
	c.resolve_node_types(asked, abs_path, mut stats)!
	c.sy_prefetch_symbols(asked)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for class in classes {
		if !class.has_super {
			continue
		}
		super_type := c.sy_instance_type(class.super_class)!
		if super_type.is_null() || !c.sy_extends_class(super_type, ['Command'])! {
			continue
		}
		mut options := class.node
		mut has_options := false
		mut autoload := class.node
		mut has_autoload := false
		for i, decorator in class.decorators {
			if !class.has_callee[i] {
				continue
			}
			name := c.sy_export_name(c.sy_symbol_at(class.callees[i])!)!
			if name == '' {
				continue
			}
			if _ := sy_decorator_call(decorator) {
				if name == 'Options' {
					if argument := sy_first_argument(decorator) {
						options = argument
						has_options = true
					} else {
						has_options = false
					}
				} else if name == 'AutoLoad' {
					autoload = decorator
					has_autoload = true
				}
			} else if name == 'AutoLoad' {
				autoload = decorator
				has_autoload = true
			}
		}
		if !has_options && !has_autoload {
			continue
		}
		command := sy_class_of_extends(c.sy_node_at(class.super_class)!)
		if !command.exists() {
			continue
		}
		valid, known := c.sy_ge_declared_groups(command)!
		if !known {
			continue
		}
		if has_options {
			c.sy_ge_check_options(options, valid, mut findings)!
		}
		if has_autoload {
			c.sy_ge_check_autoload(autoload, abs_path, valid, mut findings)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += classes.len
	return findings
}

// sy_ge_class_of_symbol ports classOfSymbol: the class the symbol, after an alias, is declared by.
fn (mut c Checker) sy_ge_class_of_symbol(symbol SymbolResponse) !SyNode {
	if symbol.is_null() {
		return SyNode{}
	}
	resolved := c.sy_unalias(symbol)!
	if resolved.is_null() || resolved.value_declaration == '' {
		return SyNode{}
	}
	declaration := c.sy_node_of_handle(resolved.value_declaration)!
	return if declaration.kind() in [sy_kind_class_declaration, sy_kind_class_expression] {
		declaration
	} else {
		SyNode{}
	}
}

// sy_ge_is_sub_command ports isSubCommand, with classInstanceType: the declared type of the class
// when it has a name, or what the type of the class constructs.
fn (mut c Checker) sy_ge_is_sub_command(class SyNode) !bool {
	mut t := TypeResponse{}
	name := class.child('name')
	if name.exists() {
		symbol := c.sy_symbol_of(name)!
		if !symbol.is_null() {
			declared := c.sy_declared_type(symbol)!
			if declared.flags & type_flag_object != 0 {
				t = declared
			}
		}
	}
	if t.is_null() {
		t = c.sy_construct_return(c.sy_type_of(class)!)!
	}
	return !t.is_null() && c.sy_extends_class(t, ['SubCommand'])!
}

// sy_ge_group_of ports groupOf: the literal name the first seyfert `@Group(...)` of the class gives
// (its second argument, or its only one).
fn (mut c Checker) sy_ge_group_of(class SyNode) !(string, bool) {
	for decorator in class.decorators() {
		expression := decorator.child('expression')
		if expression.kind() != sy_kind_call_expression {
			continue
		}
		if c.sy_export_name(c.sy_symbol_of(expression.child('expression'))!)! != 'Group' {
			continue
		}
		arguments := expression.list('arguments')
		if arguments.len == 0 {
			return '', false
		}
		value := sy_string_literal_value(if arguments.len >= 2 {
			arguments[1]
		} else {
			arguments[0]
		}) or {
			return '', false
		}
		return value, true
	}
	return '', false
}

// sy_ge_resolve_array_literal and sy_ge_resolve_groups_object port resolveArrayLiteral and
// resolveGroupsObject: through `const` bindings and imports (and `defineGroups(...)`).
fn (mut c Checker) sy_ge_resolve_array_literal(n SyNode, mut seen map[string]bool) !SyNode {
	expression := sy_unwrap(n)
	if !expression.exists() || expression.handle() in seen {
		return SyNode{}
	}
	seen[expression.handle()] = true
	kind := expression.kind()
	if kind == sy_kind_array_literal_expression {
		return expression
	}
	if kind == sy_kind_identifier || kind == sy_kind_property_access_expression {
		initializer := c.sy_const_initializer(expression)!
		if initializer.exists() {
			return c.sy_ge_resolve_array_literal(initializer, mut seen)!
		}
	}
	return SyNode{}
}

fn (mut c Checker) sy_ge_resolve_groups_object(n SyNode, mut seen map[string]bool) !SyNode {
	expression := sy_unwrap(n)
	if !expression.exists() || expression.handle() in seen {
		return SyNode{}
	}
	seen[expression.handle()] = true
	match expression.kind() {
		sy_kind_object_literal_expression {
			return expression
		}
		sy_kind_call_expression {
			arguments := expression.list('arguments')
			if c.sy_export_name(c.sy_symbol_of(expression.child('expression'))!)! == 'defineGroups'
				&& arguments.len > 0 {
				return c.sy_ge_resolve_groups_object(arguments[0], mut seen)!
			}
		}
		sy_kind_identifier, sy_kind_property_access_expression {
			initializer := c.sy_const_initializer(expression)!
			if initializer.exists() {
				return c.sy_ge_resolve_groups_object(initializer, mut seen)!
			}
		}
		else {}
	}
	return SyNode{}
}

// sy_ge_static_key ports staticKey: the key of an identifier or a string, or of a computed string.
fn sy_ge_static_key(name SyNode) ?string {
	match name.kind() {
		sy_kind_computed_property_name {
			expression := name.child('expression')
			if expression.kind() in [sy_kind_string_literal, sy_kind_no_substitution_template_literal] {
				return expression.literal_text()
			}
			return none
		}
		sy_kind_identifier {
			return name.text()
		}
		sy_kind_string_literal {
			return name.literal_text()
		}
		else {
			return none
		}
	}
}

// sy_ge_add_aliases ports addAliases: the literal `aliases` of a group's definition; false when the
// definition cannot be read.
fn (mut c Checker) sy_ge_add_aliases(definition SyNode, mut groups map[string]bool) !bool {
	mut seen := map[string]bool{}
	object := c.sy_resolve_object_literal(definition, mut seen)!
	if !object.exists() || object.list('properties').any(it.kind() == sy_kind_spread_assignment) {
		return false
	}
	aliases := sy_object_property(object, 'aliases')
	if !aliases.exists() {
		return true
	}
	mut array_seen := map[string]bool{}
	array := c.sy_ge_resolve_array_literal(aliases, mut array_seen)!
	if !array.exists() {
		return false
	}
	for element in array.list('elements') {
		alias := sy_string_literal_value(element) or { return false }
		groups[alias] = true
	}
	return true
}

// sy_ge_collect_from_object ports collectFromObject: the groups of a `@Groups` object, its spreads
// included; false when one cannot be read.
fn (mut c Checker) sy_ge_collect_from_object(object SyNode, mut groups map[string]bool, mut seen map[string]bool) !bool {
	if object.handle() in seen {
		return true
	}
	seen[object.handle()] = true
	for property in object.list('properties') {
		match property.kind() {
			sy_kind_property_assignment {
				key := sy_ge_static_key(property.child('name')) or { return false }
				if !c.sy_ge_add_aliases(property.child('initializer'), mut groups)! {
					return false
				}
				groups[key] = true
			}
			sy_kind_shorthand_property_assignment {
				value := c.client.shorthand_assignment_value_symbol(c.snapshot, c.project,
					property.handle())!
				initializer := c.sy_symbol_const_initializer(c.sy_unalias(value)!)!
				if !initializer.exists() || !c.sy_ge_add_aliases(initializer, mut groups)! {
					return false
				}
				groups[property.child('name').text()] = true
			}
			sy_kind_spread_assignment {
				mut spread_seen := map[string]bool{}
				spread := c.sy_ge_resolve_groups_object(property.child('expression'), mut spread_seen)!
				if !spread.exists() || !c.sy_ge_collect_from_object(spread, mut groups, mut seen)! {
					return false
				}
			}
			else {
				return false
			}
		}
	}
	return true
}

// sy_ge_declared_groups ports declaredGroups: the groups the `@Groups` and `@GroupsT` of the
// command and of the classes it extends declare, up to a seyfert class; false when they cannot be
// known (a declaration file, a `groups` or `__tGroups` member, a definition that cannot be read).
fn (mut c Checker) sy_ge_declared_groups(node SyNode) !(map[string]bool, bool) {
	mut groups := map[string]bool{}
	mut seen := map[string]bool{}
	mut current := node
	for current.exists() {
		if current.handle() in seen || sy_is_declaration_file(current.tree.path) {
			return groups, false
		}
		seen[current.handle()] = true
		for member in current.list('members') {
			name := member.child('name')
			if name.kind() == sy_kind_identifier && name.text() in ['groups', '__tGroups'] {
				return groups, false
			}
		}
		for decorator in current.decorators() {
			expression := decorator.child('expression')
			is_call := expression.kind() == sy_kind_call_expression
			callee := if is_call { expression.child('expression') } else { expression }
			name := c.sy_export_name(c.sy_symbol_of(callee)!)!
			if name !in ['Groups', 'GroupsT'] {
				continue
			}
			arguments := if is_call { expression.list('arguments') } else { []SyNode{} }
			mut object := SyNode{}
			if arguments.len > 0 && arguments[0].kind() != sy_kind_spread_element {
				mut object_seen := map[string]bool{}
				object = c.sy_ge_resolve_groups_object(arguments[0], mut object_seen)!
			}
			mut collect_seen := map[string]bool{}
			if !object.exists() || !c.sy_ge_collect_from_object(object, mut groups, mut collect_seen)! {
				return groups, false
			}
		}
		base := sy_extends_expression(current)
		if !base.exists() {
			return groups, false
		}
		symbol := c.sy_symbol_of(base)!
		if c.sy_export_name(symbol)! != '' {
			return groups, true
		}
		current = c.sy_ge_class_of_symbol(symbol)!
	}
	return groups, false
}

// sy_ge_check_options ports checkOptions: the subcommands an `@Options` array lists.
fn (mut c Checker) sy_ge_check_options(options C.TSNode, valid map[string]bool, mut findings []Finding) ! {
	if node_kind(options) == 'array' {
		for element in named_children(options) {
			if node_kind(element) == 'spread_element' {
				continue
			}
			sub := c.sy_ge_class_of_symbol(c.sy_symbol_at(unwrap_parens(element))!)!
			if !sub.exists() || !c.sy_ge_is_sub_command(sub)! {
				continue
			}
			group, has_group := c.sy_ge_group_of(sub)!
			if has_group && group !in valid {
				findings << Finding{
					stmt:       position_of(unwrap_parens(element))
					message_id: 'unknownGroup'
					data:       {
						'group': group
					}
				}
			}
		}
		return
	}
	argument := c.sy_node_at(options)!
	if !argument.exists() {
		return
	}
	mut seen := map[string]bool{}
	array := c.sy_ge_resolve_array_literal(argument, mut seen)!
	if !array.exists() {
		return
	}
	for element in array.list('elements') {
		sub := c.sy_ge_class_of_symbol(c.sy_symbol_of(element)!)!
		if !sub.exists() || !c.sy_ge_is_sub_command(sub)! {
			continue
		}
		group, has_group := c.sy_ge_group_of(sub)!
		if has_group && group !in valid {
			findings << Finding{
				stmt:       position_of(options)
				message_id: 'unknownGroup'
				data:       {
					'group': group
				}
			}
		}
	}
}

// sy_ge_check_autoload ports checkAutoload: the default export of each TypeScript file of the
// directory of the command and below it (fs.readdirSync with `recursive`: a directory after
// another, the names of each in byte order), when the program has it (program.getSourceFile,
// which on Windows ignores case and the kind of slash: tsgo.path_key).
fn (mut c Checker) sy_ge_check_autoload(decorator C.TSNode, abs_path string, valid map[string]bool, mut findings []Finding) ! {
	directory := os.dir(abs_path)
	mut program := map[string]bool{}
	for file in c.client.source_file_names(c.snapshot, c.project)! {
		program[tsgo.path_key(file)] = true
	}
	command := tsgo.path_key(abs_path)
	for entry in sy_ge_read_dir_recursive(directory) {
		absolute := os.join_path(directory, entry)
		key := tsgo.path_key(absolute)
		if key == command || !absolute.ends_with('.ts') || absolute.ends_with('.d.ts')
			|| entry.contains('node_modules') || key !in program {
			continue
		}
		tree := c.declaration_ast(absolute)!
		sub := c.sy_ge_default_exported_class(SyNode{ tree: tree, index: 1 })!
		if !sub.exists() || !c.sy_ge_is_sub_command(sub)! {
			continue
		}
		group, has_group := c.sy_ge_group_of(sub)!
		if !has_group || group in valid {
			continue
		}
		name := sub.child('name')
		findings << Finding{
			stmt:       position_of(decorator)
			message_id: 'unknownGroupAutoload'
			data:       {
				'group': group
				'sub':   if name.exists() { name.text() } else { '(default export)' }
				'file':  entry.replace('\\', '/')
			}
		}
	}
}

// sy_ge_read_dir_recursive is what Node's fs.readdirSync(directory, { recursive: true }) gives: the
// paths of the entries relative to the directory, a directory after another in the order found,
// the names of each in byte order (libuv's scandir sorts them with strcmp).
fn sy_ge_read_dir_recursive(base string) []string {
	mut out := []string{}
	mut queue := [base]
	for i := 0; i < queue.len; i++ {
		mut entries := os.ls(queue[i]) or { continue }
		entries.sort()
		for name in entries {
			path := os.join_path(queue[i], name)
			out << path[base.len + 1..]
			if os.is_dir(path) {
				queue << path
			}
		}
	}
	return out
}

// sy_ge_default_exported_class ports defaultExportedClass: an `export default class`, or the class
// of an `export default` expression.
fn (mut c Checker) sy_ge_default_exported_class(source SyNode) !SyNode {
	for statement in source.list('statements') {
		if statement.kind() == sy_kind_class_declaration
			&& statement.has_modifier(sy_kind_export_keyword)
			&& statement.has_modifier(sy_kind_default_keyword) {
			return statement
		}
		if statement.kind() == sy_kind_export_assignment
			&& !statement.tree.node_is_export_equals(statement.index) {
			expression := sy_unwrap(statement.child('expression'))
			if expression.kind() == sy_kind_class_expression {
				return expression
			}
			found := c.sy_ge_class_of_symbol(c.sy_symbol_of(expression)!)!
			if found.exists() {
				return found
			}
		}
	}
	return SyNode{}
}
