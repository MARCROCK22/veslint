module rules

import estree
import time
import treesitter { node_end, node_start }

// Port of the `unicorn/no-static-only-class` rule of eslint-plugin-unicorn 79.0.0 (it has no
// options), with its fix.

const unsoc_messages = {
	'no-static-only-class': 'Use an object instead of a class with only static members.'
}

// Keywords that only mean something inside a class, so they cannot survive the move to an object
// literal.
const unsoc_class_only_keywords = ['this', 'super', 'new.target']

fn (mut c Checker) lint_unicorn_no_static_only_class(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	tokens := c.un_tokens(t)
	for node in 0 .. t.nodes.len {
		if t.typ(node) !in [.class_declaration, .class_expression] {
			continue
		}
		stats.checked++
		if t.node(node, .super_class) != none
			|| (t.list(node, .decorators) or { []int{} }).len > 0 {
			continue
		}
		body := t.node(node, .body) or { continue }
		if t.typ(body) != .class_body {
			continue
		}
		members := t.list(body, .body) or { []int{} }
		if members.len == 0 || members.any(!unsoc_is_static_member(t, it)) {
			continue
		}
		// getClassHeadLocation: from the class to the token before its body.
		before_body := tokens.before(t.nodes[body].start, false) or { continue }
		mut has_fix := false
		mut fix := Fix{}
		if fixes := c.unsoc_switch_class_to_object(root, t, tokens, node) {
			has_fix, fix = c.merge_fixes(fixes)!
		}
		findings << Finding{
			stmt:       c.position_range(t.nodes[node].start, before_body.end)
			message_id: 'no-static-only-class'
			has_fix:    has_fix
			fix:        fix
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// unsoc_is_static_member ports isStaticMember.
fn unsoc_is_static_member(t &estree.EsTree, node int) bool {
	// Avoid matching unexpected nodes, like a static block.
	if node < 0 || t.typ(node) !in [.property_definition, .method_definition] {
		return false
	}
	key := t.node(node, .key) or { return false }
	if !(t.flag(node, .static_) or { false }) || t.typ(key) == .private_identifier {
		return false
	}
	// TypeScript class: an `override` member needs its base class, and an object literal has no
	// `override` modifier.
	return !((t.flag(node, .declare_) or { false }) || (t.flag(node, .readonly) or { false })
		|| (t.flag(node, .override) or { false }) || t.prop(node, .accessibility) != none
		|| (t.list(node, .decorators) or { []int{} }).len > 0)
}

// unsoc_references_class_name ports referencesClassName: a reference to the class's name is in the
// range of `value`.
fn (mut c Checker) unsoc_references_class_name(root C.TSNode, t &estree.EsTree, value int, id int) bool {
	if id < 0 || value < 0 {
		return false
	}
	ts := t.ts_node(id) or { return false }
	tree := c.scope_tree(root)
	variable := tree.find_variable(tree.get_scope(ts), t.string_of(id, .name) or { return false },
		-1)
	if variable < 0 {
		return false
	}
	start, end := t.nodes[value].start, t.nodes[value].end
	for r in tree.variables[variable].references {
		identifier := tree.references[r].identifier
		if node_start(identifier) >= start && node_end(identifier) <= end {
			return true
		}
	}
	return false
}

// unsoc_switch_class_to_object ports switchClassToObject: the fixes, none when the class cannot
// become an object.
fn (mut c Checker) unsoc_switch_class_to_object(root C.TSNode, t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	if (t.flag(node, .declare_) or { false }) || (t.flag(node, .abstract_) or { false })
		|| (t.list(node, .implements_) or { []int{} }).len > 0 {
		return none
	}
	id := t.node(node, .id) or { -1 }
	is_expression := t.typ(node) == .class_expression
	if is_expression && id >= 0 {
		return none
	}
	parent := t.nodes[node].parent
	is_export_default := t.typ(node) == .class_declaration && parent >= 0
		&& t.typ(parent) == .export_default_declaration
		&& t.node(parent, .declaration) or { -1 } == node
	if is_export_default && id >= 0 {
		return none
	}
	body := t.node(node, .body)?
	members := t.list(body, .body) or { []int{} }
	for member in members {
		// A computed key is evaluated while the class is being created, where the class binding is
		// initialized, but the `const` the class becomes is still in its temporal dead zone.
		if c.unsoc_references_class_name(root, t, t.node(member, .key) or { -1 }, id) {
			return none
		}
		// This is a stupid way to check if the initializer of a `PropertyDefinition` uses `this`,
		// `super` or `new.target`, which only exist in a class context.
		value := t.node(member, .value) or { -1 }
		value_text := if value >= 0 { c.un_text(t, value) } else { '' }
		uses_class_only_keyword := value_text != ''
			&& unsoc_class_only_keywords.any(value_text.contains(it))
		if t.typ(member) == .property_definition && (t.node(member, .type_annotation) != none
			|| uses_class_only_keyword || c.unsoc_references_class_name(root, t, member, id)) {
			return none
		}
	}
	mut fixes := []Fix{}
	class_token := un_first_token(t, tokens, node, 0)?
	if is_export_default || is_expression {
		// A concise arrow body is an `AssignmentExpression`, so a bare `{` there would be parsed as
		// a block body: `() => class {}` has to become `() => ({})`.
		before_class := tokens.before(class_token.start, false)
		is_concise_arrow_body := if token := before_class {
			c.token_text(token) == '=>'
		} else {
			false
		}
		// There are comments after the keyword, and `{` is not on the same line.
		if is_expression && c.un_unparenthesized_keyword_argument_parent(t, tokens, node) != none
			&& !un_same_line(t, t.nodes[body].start, t.nodes[parent].start)
			&& c.src[class_token.end..t.nodes[body].start].trim_space() != '' {
			fixes << fix_replace_range(class_token.start, class_token.end, '{')
			opening_brace := un_first_token(t, tokens, body, 0)?
			fixes << fix_remove_range(opening_brace.start, opening_brace.end)
		} else {
			fixes << fix_replace_range(class_token.start, class_token.end, if is_concise_arrow_body {
				'('
			} else {
				''
			})
			// Avoid breaking `return class\n{};`.
			fixes << c.un_remove_spaces_after(class_token.end)
		}
		if is_concise_arrow_body {
			fixes << fix_insert_at(t.nodes[body].end, ')')
		}
		// `export default {…}` is an expression: a following `(`, `[`, `` ` ``, `+`, `-` or `/`
		// would continue it instead of starting a new statement.
		if is_export_default {
			last_token := un_last_token(t, tokens, node)?
			token_after := tokens.after(last_token.end, false)
			code := if token := token_after { c.token_text(token) } else { '' }
			if c.unb_needs_semicolon(t, tokens, last_token, code) {
				fixes << fix_insert_at(last_token.end, ';')
			}
		}
	} else {
		fixes << fix_replace_range(class_token.start, class_token.end, 'const')
		fixes << fix_insert_at(t.nodes[body].start, '= ')
		fixes << fix_insert_at(t.nodes[body].end, ';')
	}
	for member in members {
		fixes << c.unsoc_switch_class_member_to_object_property(t, tokens, member)?
	}
	return fixes
}

// unsoc_switch_class_member_to_object_property ports switchClassMemberToObjectProperty.
fn (c &Checker) unsoc_switch_class_member_to_object_property(t &estree.EsTree, tokens &SourceTokens, node int) ?[]Fix {
	mut fixes := []Fix{}
	static_token := un_first_token(t, tokens, node, 0)?
	if c.token_text(static_token) != 'static' {
		return none
	}
	fixes << fix_remove_range(static_token.start, static_token.end)
	fixes << c.un_remove_spaces_after(static_token.end)
	is_property := t.typ(node) == .property_definition
	maybe_semicolon := if is_property {
		un_last_token(t, tokens, node)
	} else {
		tokens.after(t.nodes[node].end, false)
	}
	semicolon := maybe_semicolon or { SourceToken{} }
	has_semicolon := maybe_semicolon != none && c.token_is(semicolon, ';')
	if is_property {
		key := t.node(node, .key)?
		if t.node(node, .value) != none {
			// A computed key may have `]` after the key.
			equal := c.un_token_after_punctuator(tokens, t.nodes[key].end, '=')?
			fixes << fix_replace_range(equal.start, equal.end, ':')
		} else if has_semicolon {
			fixes << fix_insert_at(semicolon.start, ': undefined')
		} else {
			fixes << fix_insert_at(t.nodes[node].end, ': undefined')
		}
	}
	fixes << if has_semicolon {
		fix_replace_range(semicolon.start, semicolon.end, ',')
	} else {
		fix_insert_at(t.nodes[node].end, ',')
	}
	return fixes
}
