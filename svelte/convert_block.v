module svelte

// Blocks (src/parser/converts/block.ts).

// start_block_index is startBlockIndex: the last `{` at or before end_index whose next
// non-whitespace text starts with `block`.
fn (c &Conv) start_block_index(end_index int, block string) int {
	mut i := if end_index >= c.code.len { c.code.len - 1 } else { end_index }
	for i >= 0 {
		if c.code[i] == `{` {
			mut next := i + 1
			for next < c.code.len && is_space_at(c.code, next) {
				_, n := code_point_at(c.code, next)
				next += n
			}
			if next < c.code.len && at_(c.code, next, block) {
				return i
			}
		}
		i--
	}
	return -1
}

fn (c &Conv) fragment_end(nodes []int, before_end int) int {
	if nodes.len > 0 {
		return c.ca.nodes[nodes.last()].end
	}
	return before_end
}

// close_after is `code.indexOf("}", from) + 1`.
fn (c &Conv) close_after(from int) int {
	return c.index_of_from('}', from) + 1
}

// start_block_index_for_else is startBlockIndexForElse.
fn (c &Conv) start_block_index_for_else(else_nodes []int, before_nodes []int, last_end int) int {
	if else_nodes.len > 0 {
		ch := c.ca.nodes[else_nodes[0]]
		if ch.typ == .if_block && ch.elseif {
			content_start := c.ca.exprs[ch.expression].start
			if content_start <= ch.start {
				return c.start_block_index(content_start - 1, ':else')
			}
		}
		return c.start_block_index(ch.start, ':else')
	}
	before_end := c.fragment_end(before_nodes, c.close_after(last_end))
	return c.start_block_index(before_end, ':else')
}

// mustache_block_tokens is extractMustacheBlockTokens.
fn (mut c Conv) mustache_block_tokens(node int, start_only bool) {
	n := c.doc.nodes[node]
	s := c.first_non_space(n.start + 1)
	mut e := s + 1
	for e < c.code.len && c.code[e] != `}` && !is_space_at(c.code, e) {
		e++
	}
	c.add_token('MustacheKeyword', s, e)
	if start_only {
		return
	}
	mut end_end := n.end - 2
	for end_end >= 0 && is_space_at(c.code, end_end) {
		end_end--
	}
	end_end++
	mut end_start := end_end - 1
	for end_start >= 0 {
		ch := c.code[end_start]
		if ch == `{` || ch == `/` || is_space_at(c.code, end_start) {
			break
		}
		end_start--
	}
	c.add_token('MustacheKeyword', end_start, end_end)
}

fn (mut c Conv) convert_if(ch int, parent int, elseif_start int) int {
	cn := c.ca.nodes[ch]
	elseif := elseif_start >= 0
	node_start := c.start_block_index(if elseif { elseif_start } else { cn.start }, if elseif {
		':else'
	} else {
		'#if'
	})
	ifb := c.add(SNode{
		typ:    .if_block
		elseif: elseif
		start:  node_start
		end:    cn.end
		parent: parent
	})
	if_let := c.nest_if_block(cn.expression, ifb)
	consequent := c.ca.fragments[cn.consequent]
	kids := c.convert_trimmed(consequent, ifb)
	c.doc.nodes[ifb].children << kids
	if elseif {
		at := c.index_of_from('if', node_start)
		c.add_token('MustacheKeyword', at, at + 2)
	}
	c.mustache_block_tokens(ifb, elseif)
	if cn.alternate < 0 {
		c.close_scope()
		return ifb
	}
	c.begin_else(if_let)
	else_nodes := c.ca.fragments[cn.alternate]
	else_start := c.start_block_index_for_else(else_nodes, consequent, c.ca.exprs[cn.expression].end)
	if else_nodes.len == 1 {
		e0 := c.ca.nodes[else_nodes[0]]
		if e0.typ == .if_block && e0.elseif {
			eb := c.add(SNode{
				typ:    .else_block
				elseif: true
				start:  else_start
				end:    e0.end
				parent: ifb
			})
			c.doc.nodes[ifb].else_ = eb
			inner := c.convert_if(else_nodes[0], eb, else_start)
			c.doc.nodes[eb].end = c.doc.nodes[inner].end
			c.doc.nodes[eb].children = [inner]
			c.close_scope()
			return ifb
		}
	}
	eb := c.add(SNode{
		typ:    .else_block
		elseif: false
		start:  else_start
		end:    c.fragment_end(else_nodes, c.close_after(else_start + 5))
		parent: ifb
	})
	c.doc.nodes[ifb].else_ = eb
	c.nest_block(eb, [])
	ekids := c.convert_trimmed(else_nodes, eb)
	c.doc.nodes[eb].children << ekids
	c.close_scope()
	c.close_scope()
	c.mustache_block_tokens(eb, true)
	return ifb
}

fn (mut c Conv) convert_each(ch int, parent int) int {
	cn := c.ca.nodes[ch]
	node_start := c.start_block_index(cn.start, '#each')
	eb := c.add(SNode{
		typ:    .each_block
		start:  node_start
		end:    cn.end
		parent: parent
	})
	mut idx_start := -1
	mut idx_end := -1
	if cn.has_index && cn.index != '' {
		from := if cn.context >= 0 {
			c.ca.exprs[cn.context].end
		} else {
			c.ca.exprs[cn.expression].end
		}
		idx_start = c.index_of_from(cn.index, from)
		idx_end = idx_start + cn.index.len
	}
	c.nest_each_block(cn.expression, cn.context, idx_start, idx_end, eb)
	if cn.context >= 0 {
		at := c.index_of_from('as', c.ca.exprs[cn.expression].end)
		c.add_token('Keyword', at, at + 2)
	}
	if cn.key >= 0 {
		c.add_expression(cn.key, eb, '', .each_key, '')
	}
	body := c.ca.fragments[cn.body]
	kids := c.convert_trimmed(body, eb)
	c.doc.nodes[eb].children << kids
	c.close_scope()
	c.mustache_block_tokens(eb, false)
	if cn.fallback < 0 {
		return eb
	}
	fallback := c.ca.fragments[cn.fallback]
	last_end := if cn.key >= 0 {
		c.ca.exprs[cn.key].end
	} else if idx_start >= 0 {
		idx_end
	} else if cn.context >= 0 {
		c.ca.exprs[cn.context].end
	} else {
		c.ca.exprs[cn.expression].end
	}
	else_start := c.start_block_index_for_else(fallback, body, last_end)
	el := c.add(SNode{
		typ:    .else_block
		elseif: false
		start:  else_start
		end:    c.fragment_end(fallback, else_start)
		parent: eb
	})
	c.doc.nodes[eb].else_ = el
	c.nest_block(el, [])
	ekids := c.convert_trimmed(fallback, el)
	c.doc.nodes[el].children << ekids
	c.close_scope()
	c.mustache_block_tokens(el, true)
	return eb
}

fn (mut c Conv) convert_await(ch int, parent int) int {
	cn := c.ca.nodes[ch]
	node_start := c.start_block_index(cn.start, '#await')
	ab := c.add(SNode{
		typ:    .await_block
		kind:   'await'
		start:  node_start
		end:    cn.end
		parent: parent
	})
	c.add_expression(cn.expression, ab, '', .expression, '')
	expr_end := c.ca.exprs[cn.expression].end
	if cn.pending >= 0 {
		pending := c.ca.fragments[cn.pending]
		pb := c.add(SNode{
			typ:    .await_pending_block
			start:  node_start
			end:    c.fragment_end(pending, c.close_after(expr_end))
			parent: ab
		})
		c.nest_block(pb, [])
		kids := c.convert_children(pending, pb)
		c.doc.nodes[pb].children << kids
		c.doc.nodes[ab].pending = pb
		c.close_scope()
	}
	if cn.then >= 0 {
		then := c.ca.fragments[cn.then]
		await_then := cn.pending < 0
		if await_then {
			c.doc.nodes[ab].kind = 'await-then'
		}
		then_start := if c.doc.nodes[ab].pending >= 0 {
			from := if cn.await_value >= 0 {
				c.ca.exprs[cn.await_value].start
			} else if then.len > 0 {
				c.ca.nodes[then[0]].start
			} else {
				c.doc.nodes[c.doc.nodes[ab].pending].end
			}
			c.start_block_index(from, ':then')
		} else {
			node_start
		}
		tb := c.add(SNode{
			typ:        .await_then_block
			await_then: await_then
			start:      then_start
			end:        c.fragment_end(then, c.close_after(if cn.await_value >= 0 {
				c.ca.exprs[cn.await_value].end
			} else {
				then_start + 5
			}))
			parent:     ab
		})
		if cn.await_value >= 0 {
			c.nest_then_value(cn, tb)
		} else {
			c.nest_block(tb, [])
		}
		kids := c.convert_children(then, tb)
		c.doc.nodes[tb].children << kids
		if c.doc.nodes[ab].pending >= 0 {
			c.mustache_block_tokens(tb, true)
		} else {
			at := c.index_of_from('then', expr_end)
			c.add_token('MustacheKeyword', at, at + 4)
		}
		c.doc.nodes[ab].then = tb
		c.close_scope()
	}
	if cn.catch_ >= 0 {
		catch_nodes := c.ca.fragments[cn.catch_]
		await_catch := cn.pending < 0 && cn.then < 0
		if await_catch {
			c.doc.nodes[ab].kind = 'await-catch'
		}
		before := if c.doc.nodes[ab].then >= 0 {
			c.doc.nodes[ab].then
		} else {
			c.doc.nodes[ab].pending
		}
		catch_start := if before >= 0 {
			from := if cn.await_error >= 0 {
				c.ca.exprs[cn.await_error].start
			} else if catch_nodes.len > 0 {
				c.ca.nodes[catch_nodes[0]].start
			} else {
				c.doc.nodes[before].end
			}
			c.start_block_index(from, ':catch')
		} else {
			node_start
		}
		cb := c.add(SNode{
			typ:         .await_catch_block
			await_catch: await_catch
			start:       catch_start
			end:         c.fragment_end(catch_nodes, c.close_after(if cn.await_error >= 0 {
				c.ca.exprs[cn.await_error].end
			} else {
				catch_start + 6
			}))
			parent:      ab
		})
		if cn.await_error >= 0 {
			s, e := c.node_range(cn.await_error)
			c.nest_block(cb, [
				LetParam{
					start:  s
					end:    e
					typing: 'Error'
					setter: ParamSetter{
						node:  cb
						field: 1
					}
					parent: cb
				},
			])
		} else {
			c.nest_block(cb, [])
		}
		kids := c.convert_children(catch_nodes, cb)
		c.doc.nodes[cb].children << kids
		if c.doc.nodes[ab].pending >= 0 || c.doc.nodes[ab].then >= 0 {
			c.mustache_block_tokens(cb, true)
		} else {
			at := c.index_of_from('catch', expr_end)
			c.add_token('MustacheKeyword', at, at + 5)
		}
		c.doc.nodes[ab].catch_ = cb
		c.close_scope()
	}
	c.mustache_block_tokens(ab, false)
	return ab
}

// nest_then_value is the nestBlock of a `{:then value}` with its typing (TypeScript).
fn (mut c Conv) nest_then_value(cn CNode, tb int) {
	s, e := c.node_range(cn.await_value)
	setter := ParamSetter{
		node:  tb
		field: 0
	}
	if !c.is_ts() {
		c.nest_block(tb, [LetParam{s, e, 'any', setter, tb}])
		return
	}
	ex := c.ca.exprs[cn.expression]
	expression := c.code[ex.start..ex.end]
	if c.expr_is_literal(cn.expression) {
		c.nest_block(tb, [LetParam{s, e, expression, setter, tb}])
		return
	}
	id_await := c.generate_unique_id('AwaitThenValue')
	if ex.kind == .identifier && !c.pattern_has_identifier(cn.await_value, ex.name) {
		c.append_prep(await_then_value_type(id_await), 'TSTypeAliasDeclaration')
		c.nest_block(tb, [
			LetParam{s, e, '${id_await}<(typeof ${expression})>', setter, tb},
		])
		return
	}
	id := c.generate_unique_id(expression)
	c.append_prep('const ${id} = ${expression};', 'VariableDeclaration')
	c.append_prep(await_then_value_type(id_await), 'TSTypeAliasDeclaration')
	c.nest_block(tb, [LetParam{s, e, '${id_await}<(typeof ${id})>', setter, tb}])
}

fn await_then_value_type(id string) string {
	return 'type ${id}<T> = T extends null | undefined
    ? T
    : T extends { then(value: infer F): any }
    ? F extends (value: infer V, ...args: any) => any
        ? ${id}<V>
        : never
        : T;'
}

// expr_is_literal: the compiler's expression is a Literal (a string, number, boolean, null or
// regular expression literal).
fn (c &Conv) expr_is_literal(e int) bool {
	ex := c.ca.exprs[e]
	text := c.code[ex.start..ex.end]
	if text in ['true', 'false', 'null'] {
		return true
	}
	if text.len == 0 {
		return false
	}
	f := text[0]
	if f == `"` || f == `'` {
		return text.len >= 2 && text[text.len - 1] == f && !text[1..text.len - 1].contains(f.ascii_str())
	}
	if f.is_digit() || (f == `.` && text.len > 1 && text[1].is_digit()) {
		for b in text {
			if !(b.is_alnum() || b == `.` || b == `_`) {
				return false
			}
		}
		return true
	}
	return false
}

// pattern_has_identifier is hasIdentifierFor on the compiler's pattern: whether an identifier
// of the pattern has that name.
fn (c &Conv) pattern_has_identifier(p int, name string) bool {
	ex := c.ca.exprs[p]
	if ex.kind == .identifier {
		return ex.name == name
	}
	// A destructuring pattern: its identifiers (property values, elements, rest arguments,
	// defaults' left sides). Keys of `key: value` properties and default values are not.
	text := c.code[ex.start..ex.end]
	mut js := JsScanner{
		src: text
	}
	sc := js.scan_expression(0, [], [])
	for k, t in sc.tokens {
		if t.kind != .ident || text[t.start..t.end] != name {
			continue
		}
		next := if k + 1 < sc.tokens.len {
			text[sc.tokens[k + 1].start..sc.tokens[k + 1].end]
		} else {
			''
		}
		prev := if k > 0 { text[sc.tokens[k - 1].start..sc.tokens[k - 1].end] } else { '' }
		if next == ':' && prev in ['{', ','] {
			continue // a key
		}
		if prev in ['=', '.'] {
			continue // a default value or a member
		}
		return true
	}
	return false
}

fn (mut c Conv) convert_key(ch int, parent int) int {
	cn := c.ca.nodes[ch]
	node_start := c.start_block_index(cn.start, '#key')
	kb := c.add(SNode{
		typ:    .key_block
		start:  node_start
		end:    cn.end
		parent: parent
	})
	c.add_expression(cn.expression, kb, '', .expression, '')
	c.nest_block(kb, [])
	kids := c.convert_trimmed(c.ca.fragments[cn.body], kb)
	c.doc.nodes[kb].children << kids
	c.close_scope()
	c.mustache_block_tokens(kb, false)
	return kb
}

fn (mut c Conv) convert_snippet(ch int, parent int) int {
	cn := c.ca.nodes[ch]
	node_start := c.start_block_index(cn.start, '#snippet')
	sb := c.add(SNode{
		typ:    .snippet_block
		start:  node_start
		end:    cn.end
		parent: parent
	})
	before := if cn.parameters.len > 0 {
		lp := c.ca.exprs[cn.parameters.last()]
		if lp.ann_start >= 0 { lp.ann_end } else { lp.end }
	} else {
		c.ca.exprs[cn.expression].end
	}
	close_paren := c.index_of_from(')', before)
	kind := if c.doc.nodes[parent].typ == .program { Area.snippet } else { c.current_kind }
	c.nest_snippet_block(cn, close_paren, sb, kind, parent)
	kids := c.convert_trimmed(c.ca.fragments[cn.body], sb)
	c.doc.nodes[sb].children << kids
	c.close_scope()
	c.mustache_block_tokens(sb, false)
	c.snippets << sb
	return sb
}

// nest_snippet_block is nestSnippetBlock with buildSnippetParamTypes.
fn (mut c Conv) nest_snippet_block(cn CNode, close_paren int, sb int, kind Area, parent int) {
	id := c.ca.exprs[cn.expression]
	id_start := id.start
	// Typings of the unannotated plain params of a snippet that is a child of a component.
	mut types := []ParamType{}
	pn := c.doc.nodes[parent]
	if c.is_ts() && pn.typ == .element && pn.kind == 'component' {
		props := "import('svelte').ComponentProps<typeof ${c.element_name_of(parent)}>"
		snippet_type := "('${id.name}' extends infer KEY?KEY extends keyof ${props}?NonNullable<${props}[KEY]>:any:any)"
		for k, p in cn.parameters {
			pe := c.ca.exprs[p]
			if pe.ann_start >= 0 || pe.raw == 'AssignmentPattern' || pe.raw == 'RestElement' {
				continue
			}
			types << ParamType{
				end: pe.end
				typ: '${snippet_type} extends (...args: infer A) => any ? A[${k}] : any'
			}
		}
	}
	mut part := ''
	mut cursor := id_start
	mut insertions := []Segment{}
	mut segs := []Segment{}
	for t in types {
		piece := c.code[cursor..t.end]
		segs << Segment{9 + part.len, piece.len, cursor}
		part += piece
		annotation := ': (${t.typ})'
		insertions << Segment{9 + part.len, annotation.len, -1}
		part += annotation
		cursor = t.end
	}
	last := c.code[cursor..close_paren + 1]
	segs << Segment{9 + part.len, last.len, cursor}
	part += last
	ts := c.is_ts()
	close := if ts { "return (null as unknown as import('svelte').Snippet)();}" } else { '}' }
	i := c.append_let(ScriptLet{
		kind:       .snippet_block
		node_type:  'FunctionDeclaration'
		segments:   segs
		insertions: insertions
		target:     sb
		ts_return:  ts
	}, 'function ${part}{', kind)
	c.push_scope(i, close, kind)
}

struct ParamType {
	end int
	typ string
}
