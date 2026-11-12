module rules

import tsgo { ParameterResponse, SignatureResponse, SymbolResponse, TypeResponse }
import treesitter { children, has_child_kind, node_end, node_field, node_kind, node_parent, node_start }
import offsets { utf16_offsets }

// Type queries to tsgo, with caches by id. The type of each expression is requested per node
// (getTypeAtLocations), and it is the exact one, like checker.getTypeAtLocation in typescript-eslint.

// Values of TypeScript 7.1.0-beta (node_modules/typescript/dist/enums/*.enum.js).
const type_flag_any = u32(1)

const type_flag_unknown = u32(2)

const type_flag_undefined = u32(4)

const type_flag_null = u32(8)

const type_flag_number = u32(64)

const type_flag_never = u32(262144)

// TypeFlags.Primitive: string, number, bigint, boolean, enum, symbols, void, undefined, null…
const type_flag_primitive = u32(12713980)

// ElementFlags.Variable (Rest | Variadic) of the elements of a tuple.
const element_flags_variable = 12

const type_flag_void = u32(16)

const type_flag_union = u32(134217728)

const type_flag_intersection = u32(268435456)

const type_flag_type_parameter = u32(524288)

const type_flag_object = u32(1048576)

// TypeFlags.StringLike: string, string literals, template literals and StringMapping.
const type_flag_string_like = u32(12583968)

// TypeFlags.NumberLike: number, number literals and enums.
const type_flag_number_like = u32(67648)

// TypeFlags.BigIntLike: bigint and its literals.
const type_flag_bigint_like = u32(4224)

// TypeFlags.BooleanLike: boolean and its literals.
const type_flag_boolean_like = u32(8448)

// TypeFlags.ESSymbolLike.
const type_flag_es_symbol_like = u32(16896)

// TypeFlags.PossiblyFalsy and TypeFlags.TypeVariable (TypeParameter | IndexedAccess).
const type_flag_possibly_falsy = u32(15868)
const type_flag_type_variable = u32(524288 | 33554432)

// TypeFlags.IndexedAccess (`T[K]`).
const type_flag_indexed_access = u32(33554432)

// Type.isLiteral(): StringLiteral | NumberLiteral | BigIntLiteral.
const type_flag_literal_value = u32(1024 | 2048 | 4096)

const type_flag_string_literal = u32(1024)
const type_flag_number_literal = u32(2048)
const type_flag_bigint_literal = u32(4096)
const type_flag_boolean_literal = u32(8192)

// SymbolFlags.Optional.
const symbol_flag_optional = u32(16777216)

// ObjectFlags.ClassOrInterface.
const object_flags_class_or_interface = u32(3)

const symbol_flag_class = u32(32)

const symbol_flag_interface = u32(64)

const symbol_flags_type = 788968

const symbol_flags_value = 111551

const object_flag_reference = u32(4)

const signature_flag_has_rest_parameter = u32(1)

const signature_kind_call = 0

const signature_kind_construct = 1

const max_type_depth = 8

// SyntaxKind of TypeScript 7.1.0-beta (dist/enums/syntaxKind.enum.js).
const syntax_kind_await_expression = u32(225)

const syntax_kind_element_access_expression = u32(214)

const syntax_kind_call_expression = u32(215)

const syntax_kind_tagged_template_expression = u32(217)

const syntax_kind_method_declaration = u32(176)

const syntax_kind_object_literal_expression = u32(212)

const syntax_kind_expression_with_type_arguments = u32(235)

const syntax_kind_type_reference = u32(185)

const syntax_kind_literal_type = u32(203)

// SyntaxKind of declarations and their parts, to look at them in the AstTree of their file
// (declaration_ast): TypeScript 7.1.0-beta values.
const syntax_kind_identifier = u32(79)
const syntax_kind_void_keyword = u32(115)
const syntax_kind_private_keyword = u32(122)
const syntax_kind_protected_keyword = u32(123)
const syntax_kind_static_keyword = u32(125)
const syntax_kind_computed_property_name = u32(169)
const syntax_kind_type_parameter = u32(170)
const syntax_kind_parameter = u32(171)
const syntax_kind_decorator = u32(172)
const syntax_kind_property_declaration = u32(174)
const syntax_kind_method_signature = u32(175)
const syntax_kind_property_access_expression = u32(213)
const syntax_kind_function_expression = u32(220)
const syntax_kind_class_expression = u32(233)
const syntax_kind_function_declaration = u32(264)
const syntax_kind_class_declaration = u32(265)
const syntax_kind_interface_declaration = u32(266)
const syntax_kind_type_alias_declaration = u32(267)
const syntax_kind_enum_declaration = u32(268)
const syntax_kind_property_assignment = u32(304)
const syntax_kind_enum_member = u32(307)
const syntax_kind_jsdoc = u32(316)
const syntax_kind_jsdoc_deprecated_tag = u32(326)

fn (mut c Checker) constituents(t TypeResponse) ![]TypeResponse {
	if (t.flags & type_flag_union) != 0 {
		return c.members_of(t)!
	}
	return [t]
}

// TypeFlags of the types without signatures, whose apparent type is not an object, a union or
// an intersection with any: Any, Unknown, Undefined, Null, Void, NonPrimitive and Never.
const type_flags_without_signatures = u32(1 | 2 | 4 | 8 | 16 | 131072 | 262144)

// signatures_of ports checker.getSignaturesOfType, which gives the signatures of the apparent
// type. tsgo is not asked what the flags of the type tell: some types have none, the type of an
// object literal has properties only, and a primitive has those of its global interface.
//
// An instance of a generic class, interface or tuple (`Array<X>`, `Promise<X>`) has the declared
// signatures of its target and those of its base types, with the type arguments applied
// (resolveObjectTypeMembers): as many as any other instance. So when one instance has none,
// the others are not asked.
fn (mut c Checker) signatures_of(t TypeResponse, kind int) ![]SignatureResponse {
	if t.flags & type_flags_without_signatures != 0 {
		return []SignatureResponse{}
	}
	if t.flags & type_flag_object != 0 {
		if t.object_flags & object_flag_object_literal != 0 {
			return []SignatureResponse{}
		}
		if t.object_flags & object_flag_reference != 0 && t.target != 0 {
			key := (u64(u32(t.target)) << 1) | u64(kind & 1)
			if c.targets_unsigned[key] {
				return []SignatureResponse{}
			}
			signatures := c.signatures(t.id, kind)!
			if signatures.len == 0 {
				c.targets_unsigned[key] = true
			}
			return signatures
		}
	} else if apparent_kind(t) >= 0 {
		return c.signatures(c.apparent_of(t)!.id, kind)
	}
	return c.signatures(t.id, kind)
}

fn (mut c Checker) signatures(type_id int, kind int) ![]SignatureResponse {
	key := '${type_id}:${kind}'
	if key in c.sig_cache {
		return c.sig_cache[key]
	}
	sigs := c.client.signatures_of_type(c.snapshot, c.project, type_id, kind)!
	c.sig_cache[key] = sigs
	return sigs
}

// aliased_symbol ports checker.getAliasedSymbol, asked once for each symbol: a namespace import
// is looked at wherever it is used.
fn (mut c Checker) aliased_symbol(symbol_id int) !SymbolResponse {
	if symbol_id !in c.aliased_cache {
		c.aliased_cache[symbol_id] = c.client.aliased_symbol(c.snapshot, c.project, symbol_id)!
	}
	return c.aliased_cache[symbol_id]
}

// index_infos ports checker.getIndexInfosOfType, asked once for each type.
fn (mut c Checker) index_infos(type_id int) ![]tsgo.IndexInfoResponse {
	if type_id !in c.index_infos_cache {
		c.index_infos_cache[type_id] = c.client.index_infos_of_type(c.snapshot, c.project,
			type_id)!
	}
	return c.index_infos_cache[type_id]
}

// assignable ports checker.isTypeAssignableTo, asked once for each pair of types. An answer tsgo
// fails to give is not kept.
fn (mut c Checker) assignable(source int, target int) !bool {
	key := (u64(u32(source)) << 32) | u64(u32(target))
	if key !in c.assignable_cache {
		c.assignable_cache[key] = c.client.is_type_assignable_to(c.snapshot, c.project,
			source, target)!
	}
	return c.assignable_cache[key]
}

fn (mut c Checker) return_type(signature_id int) !TypeResponse {
	if signature_id in c.return_cache {
		return c.return_cache[signature_id]
	}
	ret := c.client.return_type_of_signature(c.snapshot, c.project, signature_id)!
	c.return_cache[signature_id] = ret
	return ret
}

fn (mut c Checker) members_of(t TypeResponse) ![]TypeResponse {
	if t.id in c.member_cache {
		return c.member_cache[t.id]
	}
	members := c.client.types_of_type(c.snapshot, c.project, t.id) or {
		// If tsgo panics (7.0.2 did when one of the members was an empty tuple,
		// microsoft/TypeScript#63869), the type counts as one whose members are unknown, and the file
		// as not fully analyzed.
		if !tsgo.is_panic(err) {
			return err
		}
		c.too_deep++
		[]TypeResponse{}
	}
	c.member_cache[t.id] = members
	return members
}

// symbol_of ports Type.getSymbol: the response of a type already says whether it has one.
fn (mut c Checker) symbol_of(t TypeResponse) !SymbolResponse {
	if t.symbol == 0 {
		return SymbolResponse{}
	}
	if t.id in c.symbol_cache {
		return c.symbol_cache[t.id]
	}
	symbol := c.client.symbol_of_type(c.snapshot, c.project, t.id)!
	c.symbol_cache[t.id] = symbol
	return symbol
}

// TypeFlags.Instantiable: the types that stand for another one (a type parameter, an indexed
// access, a conditional type, a substitution, `keyof`, a template literal, a string mapping).
const type_flag_instantiable = u32(524288 | 33554432 | 67108864 | 16777216 | 2097152 | 4194304 | 8388608)
const type_flag_non_primitive = u32(131072)
const object_flag_mapped = u32(32)

// The primitive types by the global interface that getApparentType gives for them, in the order
// in which it asks: String, Number, BigInt, Boolean and Symbol.
const apparent_primitive_kinds = [u32(32 | 1024), u32(64 | 2048 | 65536), u32(128 | 4096),
	u32(256 | 8192), u32(512 | 16384)]
const apparent_asked = -1
const apparent_itself = -2

// apparent_kind tells from the flags of a type what getApparentType (checker.go of TypeScript
// 7.0.2) gives for it: the type itself (apparent_itself), the global interface of a primitive
// (the index of its kind in apparent_primitive_kinds), or what only tsgo knows (apparent_asked).
fn apparent_kind(t TypeResponse) int {
	if t.flags & type_flag_instantiable != 0 {
		return apparent_asked
	}
	if t.flags & type_flag_object != 0 {
		return if t.object_flags & object_flag_mapped != 0 {
			apparent_asked
		} else {
			apparent_itself
		}
	}
	if t.flags & type_flag_intersection != 0 {
		return apparent_asked
	}
	for index, kind in apparent_primitive_kinds {
		if t.flags & kind != 0 {
			return index
		}
	}
	// `object` is the empty object type, and `unknown` too without strictNullChecks.
	if t.flags & (type_flag_non_primitive | type_flag_unknown) != 0 {
		return apparent_asked
	}
	return apparent_itself
}

// apparent_of ports checker.getApparentType. tsgo is asked only for the types whose answer the
// flags do not give, and once for each kind of primitive: most types are literals, each with its
// own id.
fn (mut c Checker) apparent_of(t TypeResponse) !TypeResponse {
	if t.id in c.apparent_cache {
		return c.apparent_cache[t.id]
	}
	kind := apparent_kind(t)
	mut apparent := t
	if kind >= 0 && kind in c.apparent_kind_cache {
		apparent = c.apparent_kind_cache[kind]
	} else if kind != apparent_itself {
		apparent = c.client.apparent_type(c.snapshot, c.project, t.id)!
		if apparent.is_null() {
			apparent = t
		}
		if kind >= 0 {
			c.apparent_kind_cache[kind] = apparent
		}
	}
	c.apparent_cache[t.id] = apparent
	return apparent
}

fn (mut c Checker) constraint_of(t TypeResponse) !TypeResponse {
	if t.id in c.constraint_cache {
		return c.constraint_cache[t.id]
	}
	constraint := c.client.constraint_of_type_parameter(c.snapshot, c.project, t.id)!
	c.constraint_cache[t.id] = constraint
	return constraint
}

// bases_of gives the base types of the declared type of a class or interface.
fn (mut c Checker) bases_of(symbol_id int) ![]TypeResponse {
	if symbol_id in c.base_cache {
		return c.base_cache[symbol_id]
	}
	declared := c.client.declared_type_of_symbol(c.snapshot, c.project, symbol_id)!
	mut bases := []TypeResponse{}
	if !declared.is_null() {
		bases = c.client.base_types(c.snapshot, c.project, declared.id)!
	}
	c.base_cache[symbol_id] = bases
	return bases
}

// Types per node. To name a tree-sitter node in tsgo, veslint looks for the tsgo node with the
// same range: its `pos` is the end of the previous token (TypeScript includes the leading trivia)
// and its `end` the end of its last token, both in UTF-16 (c.tokens does not count comments,
// which tree-sitter sometimes puts at the end of a node). If there is none (tree-sitter and
// TypeScript disagree, or the code does not compile), the node has no type and rules report nothing.

fn node_key(n C.TSNode) u64 {
	return (u64(node_start(n)) << 32) | u64(node_end(n))
}

// Span is a piece of code whose type is requested: from the first token of `first` to the byte
// `end`, matched with the tsgo node of SyntaxKind `kind` (0: the innermost one with that range).
// `key` identifies it in node_types. If it is `optional`, lacking a tsgo counterpart does not
// count as an unanalyzed node.
struct Span {
	key      u64
	first    C.TSNode
	end      int
	kind     u32
	optional bool
}

fn node_span(n C.TSNode) Span {
	return Span{
		key:   node_key(n)
		first: n
		end:   node_end(n)
	}
}

// resolve_node_types requests the type of each node of `nodes` in a single request.
fn (mut c Checker) resolve_node_types(nodes []C.TSNode, abs_path string, mut stats Stats) ! {
	c.resolve_spans(nodes.map(node_span(it)), abs_path, mut stats)!
}

// resolve_spans requests the type of each span in a single request and records, by its key, the
// SyntaxKind and the handle of the matched tsgo node.
fn (mut c Checker) resolve_spans(spans []Span, abs_path string, mut stats Stats) ! {
	c.resolve_new(spans, abs_path, mut stats)!
}

// reset_file_types forgets the requested types: called when each file starts.
fn (mut c Checker) reset_file_types() {
	c.node_types = map[u64]TypeResponse{}
	c.node_kinds = map[u64]u32{}
	c.node_handles = map[u64]string{}
	c.contextual_cache = map[u64]TypeResponse{}
	c.resolved_cache = map[u64]SignatureResponse{}
	c.attempted = map[u64]bool{}
	c.file_scopes = unsafe { nil }
	c.file_tokens = unsafe { nil }
}

// resolve_new requests in a single getTypeAtLocations the types of the spans not yet tried in
// this file (another rule may have requested them already). If several spans have the same key
// with different ranges (two rules that see the same node differently), the first one with a
// tsgo counterpart wins; with none, the node counts once as unanalyzed, unless all of them are
// optional.
fn (mut c Checker) resolve_new(spans []Span, abs_path string, mut stats Stats) ! {
	mut variants := map[u64][]Span{}
	mut order := []u64{}
	for s in spans {
		if s.key in c.attempted {
			continue
		}
		if s.key !in variants {
			order << s.key
		}
		variants[s.key] << s
	}
	if order.len == 0 {
		return
	}
	mut bytes := []int{}
	for key in order {
		for s in variants[key] {
			bytes << c.tokens.last_end(node_start(s.first))
			bytes << c.tokens.last_end(s.end)
		}
	}
	units := utf16_offsets(c.src, bytes)
	if c.ast_path != abs_path {
		c.ast = c.client.source_file_ast(c.snapshot, c.project, abs_path)!
		c.ast_path = abs_path
	}
	mut keys := []u64{cap: order.len}
	mut handles := []string{cap: order.len}
	mut i := 0
	for key in order {
		c.attempted[key] = true
		mut found := false
		mut optional := true
		for s in variants[key] {
			pos, end := units[2 * i], units[2 * i + 1]
			i++
			optional = optional && s.optional
			if found {
				continue
			}
			handle := c.ast.handle(pos, end, s.kind) or { continue }
			c.node_handles[key] = handle
			c.node_kinds[key] = if s.kind != 0 { s.kind } else { c.ast.kind(pos, end) or { 0 } }
			keys << key
			handles << handle
			found = true
		}
		// An expression-like node inside a type query (`typeof import('./x')['default']`) is not an
		// expression for TypeScript: it has no counterpart and nothing to analyze.
		if !found && !optional && !inside_type_query(variants[key][0].first) {
			stats.unmatched++
		}
	}
	if handles.len == 0 {
		return
	}
	mut failed := map[int]bool{}
	types := c.request_types(handles, 0, mut failed)!
	if types.len != handles.len {
		return error('protocol: tsgo returned ${types.len} types for ${handles.len} nodes')
	}
	for j, key in keys {
		if j in failed {
			// Like a node without a tsgo counterpart: no type, no handle, and it counts as unanalyzed.
			c.node_handles.delete(key)
			c.node_kinds.delete(key)
			continue
		}
		c.node_types[key] = types[j]
	}
	stats.unmatched += failed.len
	stats.nodes += handles.len - failed.len
}

// request_types asks tsgo for the types of `handles` in a single getTypeAtLocations. When tsgo
// panics on a node it rejects the whole request (7.0.2 did on an empty array literal whose type is
// the empty tuple, like `[] as const`: microsoft/TypeScript#63869, fixed in 7.1), so the handles
// are split in halves until the ones it panics on are alone. `failed` gets their indexes, counted
// from `offset`, and their types stay empty.
fn (mut c Checker) request_types(handles []string, offset int, mut failed map[int]bool) ![]TypeResponse {
	return c.client.types_at_locations(c.snapshot, c.project, handles) or {
		if !tsgo.is_panic(err) {
			return err
		}
		if handles.len == 1 {
			failed[offset] = true
			return [TypeResponse{}]
		}
		half := handles.len / 2
		mut types := c.request_types(handles[..half], offset, mut failed)!
		types << c.request_types(handles[half..], offset + half, mut failed)!
		return types
	}
}

// declaration_ast is the AstTree of a program file, by the path of a tsgo handle (handle_path), to
// look at declarations: the current file's comes from the AST already requested; other files are
// requested once and kept for the whole run (or in the DeclarationAsts the Checker shares). An
// AstTree only holds the binary and offsets, so the copy it returns does not copy node data.
fn (mut c Checker) declaration_ast(path string) !tsgo.AstTree {
	if c.ast_path != '' && path == c.ast.path {
		return c.ast.tree
	}
	if c.shared_asts != unsafe { nil } {
		if tree := c.shared_asts.trees[path] {
			return tree
		}
		tree := c.client.source_file_ast_tree(c.snapshot, c.project, path)!
		c.shared_asts.trees[path] = tree
		return tree
	}
	if tree := c.declaration_asts[path] {
		return tree
	}
	tree := c.client.source_file_ast_tree(c.snapshot, c.project, path)!
	c.declaration_asts[path] = tree
	return tree
}

// contextual_type ports checker.getContextualType for a node requested with resolve_node_types.
// Without a contextual type (or without a tsgo node) it returns the null type.
fn (mut c Checker) contextual_type(n C.TSNode) !TypeResponse {
	key := node_key(n)
	if key !in c.contextual_cache {
		handle := c.node_handles[key] or { return TypeResponse{} }
		c.contextual_cache[key] = c.client.contextual_type(c.snapshot, c.project, handle)!
	}
	return c.contextual_cache[key]
}

// The kinds of node checker.resolveSignature takes: a call, a `new`, a tagged template, a
// decorator and the opening of a JSX element. tsgo panics on a node of another kind.
const resolvable_kinds = [u32(172), 215, 216, 217, 287, 288]
const syntax_kind_import_type = u32(207)

// resolved_signature ports checker.getResolvedSignature for a call of the file: asked once,
// whichever rules ask. Without a tsgo node for the call, a signature with id 0. The same when
// the node with the range of the call is not one TypeScript resolves: the type `import('./x')`,
// which is a call for the grammar, or code tree-sitter and TypeScript read differently, which
// counts as a node that is not analyzed.
fn (mut c Checker) resolved_signature(call C.TSNode) !SignatureResponse {
	key := node_key(call)
	if key !in c.resolved_cache {
		handle := c.node_handles[key] or { return SignatureResponse{} }
		kind := c.node_kinds[key] or { 0 }
		if kind in resolvable_kinds {
			c.resolved_cache[key] = c.client.resolved_signature(c.snapshot, c.project,
				handle)!
		} else {
			if kind != syntax_kind_import_type {
				c.too_deep++
			}
			c.resolved_cache[key] = SignatureResponse{}
		}
	}
	return c.resolved_cache[key]
}

// type_predicate ports checker.getTypePredicateOfSignature.
fn (mut c Checker) type_predicate(signature_id int) !tsgo.TypePredicateResponse {
	if signature_id !in c.predicate_cache {
		c.predicate_cache[signature_id] = c.client.type_predicate_of_signature(c.snapshot,
			c.project, signature_id)!
	}
	return c.predicate_cache[signature_id]
}

// ts_kind is the SyntaxKind of the tsgo node matched with `n` (0 if there is none).
fn (c &Checker) ts_kind(n C.TSNode) u32 {
	return c.node_kinds[node_key(n)] or { 0 }
}

// AwaitReading is how TypeScript reads a tree-sitter await_expression. Outside an async function,
// `await` followed by `(`, `[` or a template is an identifier: `await (x)` is a call, `await [x]`
// an element access and `` await `x` `` a tagged template.
enum AwaitReading {
	await_expr
	call
	tagged_template
	element_access
	other
}

// await_reading gives TypeScript's reading of an await_expression requested with resolve_spans.
// Without a tsgo counterpart it counts as an `await`.
fn (c &Checker) await_reading(n C.TSNode) AwaitReading {
	kind := c.ts_kind(n)
	return if kind == 0 || kind == syntax_kind_await_expression {
		.await_expr
	} else if kind == syntax_kind_call_expression {
		.call
	} else if kind == syntax_kind_tagged_template_expression {
		.tagged_template
	} else if kind == syntax_kind_element_access_expression {
		.element_access
	} else {
		.other
	}
}

// await_keyword_span requests the type of the `await` token of an await_expression as an
// identifier, in case TypeScript reads it that way; a real `await` has no counterpart and does
// not count.
fn await_keyword_span(n C.TSNode) ?Span {
	keyword := await_keyword(n)?
	return Span{
		key:      node_key(keyword)
		first:    keyword
		end:      node_end(keyword)
		optional: true
	}
}

// await_keyword is the `await` token of an await_expression.
fn await_keyword(n C.TSNode) ?C.TSNode {
	for child in children(n) {
		if node_kind(child) == 'await' {
			return child
		}
	}
	return none
}

// range_span requests the type of the tsgo node from the first token of `first` to the end of
// `last` (for example, the comma expression `a, b` of `await [a, b]`, not a tree-sitter node).
fn range_span(first C.TSNode, last C.TSNode) Span {
	return Span{
		key:   (u64(node_start(first)) << 32) | u64(node_end(last))
		first: first
		end:   node_end(last)
	}
}

// inside_type_query: the node is part of the operand of a `typeof` in a type.
fn inside_type_query(n C.TSNode) bool {
	mut node := n
	for _ in 0 .. max_expression_depth {
		node = node_parent(node) or { return false }
		match node_kind(node) {
			'type_query' { return true }
			'member_expression', 'subscript_expression', 'call_expression', 'arguments',
			'instantiation_expression', 'parenthesized_expression', 'import_type' {
			}
			else { return false }
		}
	}
	return false
}

// type_node_span requests the type of a type node, like getTypeAtLocation on an ESTree type node
// (getTypeFromTypeNode). Some TypeScript type nodes share their range with their child, which kind
// 0 would pick: a type reference (`Foo`, `A.B`: tsgo gives the name no type; since TypeScript 7.1
// also the types of `implements` and of an interface's `extends`) and a literal type (`'a'`, `1`,
// `null`, `true`, a template without substitutions). tree-sitter reads `bigint` as a
// type_identifier and `undefined` as a literal_type, but TypeScript has keyword types for them, the
// only nodes with their range. Every rule must request type nodes this way: the first request of a
// range in a file wins.
fn (c &Checker) type_node_span(n C.TSNode) Span {
	kind := match node_kind(n) {
		'type_identifier', 'nested_type_identifier', 'generic_type' {
			if node_kind(n) == 'type_identifier' && c.text(n) == 'bigint' {
				u32(0)
			} else if name := node_field(n, 'name') {
				// `import('./x').Y<T>` is an ImportType, the only node with its range.
				if node_kind(name) == 'import_type' { u32(0) } else { syntax_kind_type_reference }
			} else {
				syntax_kind_type_reference
			}
		}
		'literal_type' {
			if has_child_kind(n, 'undefined') { u32(0) } else { syntax_kind_literal_type }
		}
		'template_literal_type' {
			if has_child_kind(n, 'template_type') { u32(0) } else { syntax_kind_literal_type }
		}
		else {
			u32(0)
		}
	}
	return Span{
		key:   node_key(n)
		first: n
		end:   node_end(n)
		kind:  kind
	}
}

// span_type is the type of a span requested with resolve_spans, if tsgo knows it.
fn (c &Checker) span_type(s Span) ?TypeResponse {
	t := c.node_types[s.key] or { return none }
	if t.is_null() {
		return none
	}
	return t
}

// node_type is the type of a node requested with resolve_node_types, if tsgo knows it.
fn (c &Checker) node_type(n C.TSNode) ?TypeResponse {
	t := c.node_types[node_key(n)] or { return none }
	if t.is_null() {
		return none
	}
	return t
}

// type_string ports checker.typeToString.
fn (mut c Checker) type_string(t TypeResponse) !string {
	if t.id !in c.type_string_cache {
		c.type_string_cache[t.id] = c.client.type_to_string(c.snapshot, c.project, t.id)!
	}
	return c.type_string_cache[t.id]
}

// base_constraint ports checker.getBaseConstraintOfType of tsgo, which gives nothing unless the
// type stands for another one, is a union or an intersection, or is a generic tuple (a
// reference): only those are asked.
fn (mut c Checker) base_constraint(t TypeResponse) !TypeResponse {
	if t.flags & (type_flag_instantiable | type_flag_union | type_flag_intersection) == 0
		&& t.object_flags & object_flag_reference == 0 {
		return TypeResponse{}
	}
	if t.id in c.base_constraint_cache {
		return c.base_constraint_cache[t.id]
	}
	constraint := c.client.base_constraint_of_type(c.snapshot, c.project, t.id)!
	c.base_constraint_cache[t.id] = constraint
	return constraint
}

// constrained ports getConstrainedTypeAtLocation: the base constraint of the type, or the type.
fn (mut c Checker) constrained(t TypeResponse) !TypeResponse {
	constraint := c.base_constraint(t)!
	return if constraint.is_null() { t } else { constraint }
}

fn (mut c Checker) property(t TypeResponse, name string) !SymbolResponse {
	key := '${t.id}:${name}'
	if key in c.property_cache {
		return c.property_cache[key]
	}
	symbol := c.client.property_of_type(c.snapshot, c.project, t.id, name)!
	c.property_cache[key] = symbol
	return symbol
}

fn (mut c Checker) properties(t TypeResponse) ![]SymbolResponse {
	if t.id in c.properties_cache {
		return c.properties_cache[t.id]
	}
	props := c.client.properties_of_type(c.snapshot, c.project, t.id)!
	c.properties_cache[t.id] = props
	return props
}

fn (mut c Checker) symbol_type(symbol_id int) !TypeResponse {
	if symbol_id in c.symbol_type_cache {
		return c.symbol_type_cache[symbol_id]
	}
	t := c.client.type_of_symbol(c.snapshot, c.project, symbol_id)!
	c.symbol_type_cache[symbol_id] = t
	return t
}

// number_index_type ports Type.getNumberIndexType: the type of the index with a `number` key.
fn (mut c Checker) number_index_type(t TypeResponse) !TypeResponse {
	if t.id in c.number_index_cache {
		return c.number_index_cache[t.id]
	}
	mut result := TypeResponse{}
	for info in c.index_infos(t.id)! {
		if info.key_type.flags & type_flag_number != 0 {
			result = info.value_type
			break
		}
	}
	c.number_index_cache[t.id] = result
	return result
}

// well_known_property_name gives the name of the `[Symbol.<name>]` property: "__@<name>@<id>",
// where id is the one tsgo gives the symbol of `SymbolConstructor.<name>` (the id of its
// reference, not the int of the client; checked with 7.1.0-beta).
fn (mut c Checker) well_known_property_name(name string) !string {
	if name in c.well_known_names {
		return c.well_known_names[name]
	}
	mut result := '__@${name}'
	symbol := c.client.resolve_name(c.snapshot, c.project, 'Symbol', symbol_flags_value)!
	if !symbol.is_null() {
		prop := c.property(c.symbol_type(symbol.id)!, name)!
		if !prop.is_null() {
			result = '__@${name}@${prop.reference.id}'
		}
	}
	c.well_known_names[name] = result
	return result
}

// has_well_known_property ports getWellKnownSymbolPropertyOfType(…) != null.
fn (mut c Checker) has_well_known_property(t TypeResponse, name string) !bool {
	expected := c.well_known_property_name(name)!
	for prop in c.properties(t)! {
		if prop.name == expected {
			return true
		}
	}
	return false
}

fn (mut c Checker) signature_parameters(sig SignatureResponse) ![]ParameterResponse {
	if sig.id in c.parameters_cache {
		return c.parameters_cache[sig.id]
	}
	params := c.client.parameters_of_signature(c.snapshot, c.project, sig.id)!
	c.parameters_cache[sig.id] = params
	return params
}

// is_true_literal ports isTrueLiteralType. TypeScript names the boolean literal types with
// intrinsicName "true"/"false"; tsgo leaves intrinsicName out and sends `value` instead.
fn is_true_literal(t TypeResponse) bool {
	return t.flags & type_flag_boolean_literal != 0 && boolean_literal_value(t)
}

// is_false_literal ports isFalseLiteralType.
fn is_false_literal(t TypeResponse) bool {
	return t.flags & type_flag_boolean_literal != 0 && !boolean_literal_value(t)
}

fn boolean_literal_value(t TypeResponse) bool {
	value := t.value
	if value is bool {
		return value
	}
	return t.intrinsic_name == 'true'
}
