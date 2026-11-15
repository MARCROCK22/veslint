module rules

import estree
import treesitter { Ident }

// Ports of typescript-eslint 8.72.2's getNameFromMember (util/misc.ts) and getMemberHeadLoc and
// getParameterPropertyHeadLoc (util/getMemberHeadLoc.ts), on the ESTree of the estree module.

// TsmNameType is MemberNameType.
enum TsmNameType {
	private_   = 1
	quoted     = 2
	normal     = 3
	expression = 4
}

// tsm_literal_string is `${literal.value}`.
fn tsm_literal_string(t &estree.EsTree, node int) string {
	v := t.get(node, .value)
	return match v {
		string { v }
		bool { v.str() }
		f64 { js_number_to_string(v) }
		estree.BigIntValue { v.digits }
		estree.RegExpValue { tsm_regex_text(t, node) }
		else { 'null' }
	}
}

// tsm_regex_text is the text of a regular expression literal (String of its RegExp; the value of one V8 rejects is null).
fn tsm_regex_text(t &estree.EsTree, node int) string {
	regex := t.prop(node, .regex) or { return 'null' }
	// RegExp.prototype.flags lists the flags in this order.
	flags := 'dgimsuvy'.split('').filter(regex.str2.contains(it)).join('')
	return '/${regex.str}/${flags}'
}

// tsm_name_from_member ports getNameFromMember: the name of a member and its MemberNameType.
fn (c &Checker) tsm_name_from_member(t &estree.EsTree, member int) (string, TsmNameType) {
	key := t.node(member, .key) or { return '', TsmNameType.expression }
	match t.typ(key) {
		.identifier {
			return t.string_of(key, .name) or { '' }, TsmNameType.normal
		}
		.private_identifier {
			return '#${t.string_of(key, .name) or { '' }}', TsmNameType.private_
		}
		.literal {
			name := tsm_literal_string(t, key)
			if requires_quoting(name) {
				return '"${name}"', TsmNameType.quoted
			}
			return name, TsmNameType.normal
		}
		else {
			return c.src[t.nodes[key].start..t.nodes[key].end], TsmNameType.expression
		}
	}
}

// tsm_after_decorators is where a member starts after its decorators: the token after the last
// one, or the start of the member.
fn tsm_after_decorators(t &estree.EsTree, tokens &SourceTokens, member int) int {
	decorators := t.list(member, .decorators) or { []int{} }
	if decorators.len > 0 {
		if next := tokens.after(t.nodes[decorators.last()].end, false) {
			return next.start
		}
	}
	return t.nodes[member].start
}

// tsm_member_head ports getMemberHeadLoc: from after the decorators to the end of the key (its
// `]` when computed).
fn (c &Checker) tsm_member_head(t &estree.EsTree, tokens &SourceTokens, member int) Ident {
	start := tsm_after_decorators(t, tokens, member)
	key := t.node(member, .key) or { return c.position_range(start, t.nodes[member].end) }
	mut end := t.nodes[key].end
	if t.flag(member, .computed) or { false } {
		mut at := end
		for {
			token := tokens.after(at, false) or { break }
			if c.src[token.start..token.end] == ']' {
				end = token.end
				break
			}
			at = token.end
		}
	}
	return c.position_range(start, end)
}

// tsm_parameter_property_head ports getParameterPropertyHeadLoc: from after the decorators to
// the start of the parameter plus the length of the name (in UTF-16 units).
fn (c &Checker) tsm_parameter_property_head(t &estree.EsTree, tokens &SourceTokens, node int, name string) Ident {
	start := tsm_after_decorators(t, tokens, node)
	parameter := t.node(node, .parameter) or { return c.position_range(start, t.nodes[node].end) }
	mut end := t.nodes[parameter].start
	mut units := estree.utf16_units(name).len
	for units > 0 && end < c.src.len {
		b := c.src[end]
		len := if b < 0x80 {
			1
		} else if b < 0xe0 {
			2
		} else if b < 0xf0 {
			3
		} else {
			4
		}
		units -= if len == 4 { 2 } else { 1 }
		end += len
	}
	return c.position_range(start, end)
}
