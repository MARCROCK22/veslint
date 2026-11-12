module rules

import tsgo { ParameterResponse, SymbolResponse, TypeResponse }
import treesitter { has_child_kind, node_field, node_kind, node_parent }

// Calls typescript-eslint makes to the checker, over the tsgo API: getTypeOfSymbolAtLocation
// (symbol_type_at), `symbol.members` (symbol_members) and getContextualTypeForArgumentAtIndex
// (contextual_argument_type). What follows was read in the checker.go of TypeScript 7.0.2; the
// fixtures `checker-calls/` of seven rules pass with 7.1.0-beta.
//
// checker.getTypeOfSymbolAtLocation(symbol, location).
// TypeScript 7.0.2 (GetTypeOfSymbolAtLocation in checker.go) answers the type of the symbol
// (getTypeOfSymbol) except in these cases:
//   - the location is an identifier that refers to the symbol itself (alone or as the right side
//     of a property access): the answer is the type of that expression, narrowed by control flow;
//   - the location is the name of a set accessor, or the right side of a property access that is
//     written to: the answer is the write type;
//   - the symbol has an export symbol: the answer is about that one;
//   - otherwise it is getNonMissingTypeOfSymbol, which with `exactOptionalPropertyTypes` removes
//     the `undefined` an optional property is read with.
// An identifier only refers to a symbol with its name (or to the `default` export a declaration
// with that name makes), so tsgo is asked only when one of those cases may apply, and the cached
// type of the symbol is the answer in the others.

const syntax_kind_private_identifier = u32(80)

// CheckerCalls are the answers kept for the whole run.
struct CheckerCalls {
mut:
	non_missing map[int]TypeResponse     // getNonMissingTypeOfSymbol of each queried optional symbol
	members     map[int][]SymbolResponse // `symbol.members` of each queried symbol
	intrinsic   map[string]TypeResponse  // intrinsic types by the name of their getter
}

// SymbolLocation is the node getTypeOfSymbolAtLocation is asked at.
struct SymbolLocation {
	handle     string // tsgo handle of the node ('' when it has no tsgo counterpart)
	identifier string // text of the node when TypeScript reads it as an identifier ('' otherwise)
	always     bool   // a name (of a member, or the right side of an access): tsgo is always asked
}

// symbol_location is the location of a node whose type was requested with resolve_spans.
fn (c &Checker) symbol_location(n C.TSNode) SymbolLocation {
	return c.span_location(node_key(n), n)
}

// span_location is the location of a span requested with resolve_spans, by its key: `n` is the
// tree-sitter node it starts at (the node itself, for a span that is a node).
fn (c &Checker) span_location(key u64, n C.TSNode) SymbolLocation {
	handle := c.node_handles[key] or { return SymbolLocation{} }
	kind := tsgo.handle_kind(handle)
	return SymbolLocation{
		handle:     handle
		identifier: if kind in [syntax_kind_identifier, syntax_kind_private_identifier] {
			c.text(n)
		} else {
			''
		}
		always:     is_member_name(n)
	}
}

// is_member_name: the node is the name of a property (of a member, or the right side of a
// property access), the index of an element access or the name of a set accessor, whatever kind
// of name it is.
fn is_member_name(n C.TSNode) bool {
	if node_kind(n) in ['property_identifier', 'private_property_identifier'] {
		return true
	}
	parent := node_parent(n) or { return false }
	field := match node_kind(parent) {
		'subscript_expression' {
			'index'
		}
		'method_definition' {
			if !has_child_kind(parent, 'set') {
				return false
			}
			'name'
		}
		else {
			return false
		}
	}
	name := node_field(parent, field) or { return false }
	return node_key(name) == node_key(n)
}

// may_refer tells whether an identifier at the location may be a reference to a symbol with that
// (escaped) name.
fn (at SymbolLocation) may_refer(name string) bool {
	if at.always {
		return true
	}
	if at.identifier == '' {
		return false
	}
	// An identifier written with `\u…` escapes is not compared.
	return at.identifier.contains('\\') || name == 'default' || unescape_name(name) == at.identifier
}

// symbol_type_at ports checker.getTypeOfSymbolAtLocation(symbol, location) for a symbol that
// arrived whole in a response. Without a tsgo node for the location, the type of the symbol.
fn (mut c Checker) symbol_type_at(symbol SymbolResponse, at SymbolLocation) !TypeResponse {
	if at.handle != '' && symbol.export_symbol != 0 {
		return c.client.type_of_symbol_at_location(c.snapshot, c.project, symbol.id, at.handle)!
	}
	return c.symbol_id_type_at(symbol.id, symbol.name, symbol.flags, at)!
}

// parameter_type_at ports checker.getTypeOfSymbolAtLocation(parameter, location) for a parameter
// of a signature (signature_parameters).
fn (mut c Checker) parameter_type_at(param ParameterResponse, at SymbolLocation) !TypeResponse {
	return c.symbol_id_type_at(param.id, param.name, param.flags, at)!
}

fn (mut c Checker) symbol_id_type_at(symbol_id int, name string, flags u32, at SymbolLocation) !TypeResponse {
	if at.handle == '' {
		return c.symbol_type(symbol_id)!
	}
	if at.may_refer(name) {
		return c.client.type_of_symbol_at_location(c.snapshot, c.project, symbol_id, at.handle)!
	}
	if c.exact_optional_property_types && flags & symbol_flag_optional != 0 {
		// getNonMissingTypeOfSymbol: the same from every location that is not a reference.
		if symbol_id !in c.calls.non_missing {
			c.calls.non_missing[symbol_id] = c.client.type_of_symbol_at_location(c.snapshot,
				c.project, symbol_id, at.handle)!
		}
		return c.calls.non_missing[symbol_id]
	}
	return c.symbol_type(symbol_id)!
}

// escape_leading_underscores ports ts.escapeLeadingUnderscores: the name a symbol table has a
// declared name under.
fn escape_leading_underscores(name string) string {
	return if name.starts_with('__') { '_' + name } else { name }
}

// symbol_members ports `symbol.members` (getMembersOfSymbol), asked once for each symbol.
fn (mut c Checker) symbol_members(symbol_id int) ![]SymbolResponse {
	if symbol_id !in c.calls.members {
		c.calls.members[symbol_id] = c.client.members_of_symbol(c.snapshot, c.project,
			symbol_id)!
	}
	return c.calls.members[symbol_id]
}

// intrinsic ports the getters of the intrinsic types (`getAnyType`, `getNumberType`…), asked once.
fn (mut c Checker) intrinsic(method string) !TypeResponse {
	if method !in c.calls.intrinsic {
		c.calls.intrinsic[method] = c.client.intrinsic_type(method, c.snapshot, c.project)!
	}
	return c.calls.intrinsic[method]
}

// contextual_argument_type ports checker.getContextualTypeForArgumentAtIndex(call, index), which
// counts the arguments as written. checker.getContextualType of the argument makes the same call
// with the index of the argument among the effective ones (getEffectiveCallArguments), where a
// spread of a tuple stands for one argument per element: without a spread up to the argument both
// indexes are the same, and that is what is asked. With one, tsgo is asked for it (TypeScript 7.1
// has it in its API; with 7.0.2 veslint computed it from the resolved signature, and fell back to
// the argument's contextual type where the checker makes a type 7.0.2 had no id for).
fn (mut c Checker) contextual_argument_type(call C.TSNode, args []C.TSNode, index int) !TypeResponse {
	if !args[..index + 1].any(node_kind(it) == 'spread_element') {
		return c.contextual_type(args[index])!
	}
	key := node_key(call)
	handle := c.node_handles[key] or { return c.contextual_type(args[index])! }
	// tsgo panics on a node that is not a call, a `new`, a tagged template, a decorator or a JSX
	// element (see resolved_signature).
	if (c.node_kinds[key] or { 0 }) !in resolvable_kinds {
		return c.contextual_type(args[index])!
	}
	return c.client.contextual_type_for_argument(c.snapshot, c.project, handle, index)!
}
