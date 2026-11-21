module rules

import treesitter { has_child_kind, node_end, node_field, node_kind, node_parent, node_start }

// `await` as an identifier. TypeScript only reads `await` as the operator inside an async
// function or at the top level of a module, or when a name, a keyword or a literal follows it on
// its line (isAwaitExpression in its parser). Anywhere else it is a name: `await (x)` is a call,
// `await [x]` an element access, `` await `…` `` a tagged template and `await -x` a subtraction,
// and what follows belongs to that expression (`await (x).y` is `(await(x)).y`). The grammar
// always reads the operator, so the two trees differ from there on.
//
// veslint asks tsgo how it read each `await` that could be a name and, when one is, parses the
// file again with that token as an identifier of the same length: the tree is then the one
// TypeScript has, for every rule and however the expression goes on. The text of a node comes
// from the source, where the name is still `await`.

// await_identifier_byte is the byte of `await` that is replaced (by `_`) to make it a name for
// the grammar.
const await_identifier_byte = 2

// await_identifiers_source gives the source to parse again when TypeScript read some `await` of
// the tree as an identifier: the file with those tokens as names. Empty when there is none. A
// checker made without a snapshot makes it here, since only the program tells.
fn (mut c Checker) await_identifiers_source(root C.TSNode, abs_path string) !string {
	mut keywords := []C.TSNode{}
	for node in c.nodes_of_kind(root, c'await_expression') {
		keyword := await_keyword(node) or { continue }
		if !c.await_takes_operand(keyword) && !await_in_async_body(node) {
			keywords << keyword
		}
	}
	if keywords.len == 0 {
		return ''
	}
	// An identifier of TypeScript spans from the end of the previous token to the end of its own.
	mut bytes := []int{cap: 2 * keywords.len}
	for keyword in keywords {
		bytes << node_start(keyword)
		bytes << node_end(keyword)
	}
	units := c.ts_spans(bytes)
	c.make_snapshot()!
	mut ranges := []int{cap: 3 * keywords.len}
	for index in 0 .. keywords.len {
		ranges << units[2 * index]
		ranges << units[2 * index + 1]
		ranges << int(syntax_kind_identifier)
	}
	// A file tsgo does not have is reported by the first rule that asks for its types.
	identifiers := c.file_nodes(abs_path, ranges) or { return '' }
	mut source := c.parse_text().bytes()
	mut found := false
	for index, keyword in keywords {
		if identifiers[index].index != 0 {
			source[node_start(keyword) + await_identifier_byte] = `_`
			found = true
		}
	}
	return if found { source.bytestr() } else { '' }
}

// await_in_async_body: the await_expression is in the body of an async function, with no other
// function or class in between, where TypeScript always reads the operator (its await context).
// Anywhere else (the top level, a function that is not async, parameters, the members of a class)
// tsgo is asked.
fn await_in_async_body(await_node C.TSNode) bool {
	mut child := await_node
	mut node := node_parent(await_node) or { return false }
	for {
		match node_kind(node) {
			'function_declaration', 'function_expression', 'generator_function_declaration',
			'generator_function', 'arrow_function', 'method_definition' {
				body := node_field(node, 'body') or { return false }
				return node_key(body) == node_key(child) && has_child_kind(node, 'async')
			}
			'class_body', 'program' {
				return false
			}
			else {}
		}
		child = node
		node = node_parent(node) or { return false }
	}
	return false
}

// await_takes_operand: what follows the `await` token on its line starts a name, a keyword or a
// string or number literal, so TypeScript reads the operator wherever it is
// (nextTokenIsIdentifierOrKeywordOrLiteralOnSameLine). Comments are not looked through and only
// ASCII is told apart: any other `await` is asked to tsgo.
fn (c &Checker) await_takes_operand(keyword C.TSNode) bool {
	mut index := node_end(keyword)
	for index < c.src.len && c.src[index] in [` `, `\t`] {
		index++
	}
	if index >= c.src.len {
		return false
	}
	b := c.src[index]
	return b.is_letter() || b.is_digit() || b in [`_`, `$`, `"`, `'`, `\\`]
}
