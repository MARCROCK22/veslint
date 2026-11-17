module vue

import estree

// The parsers of template expressions of vue-eslint-parser (src/script/index.ts): each wraps the
// decoded text in the code it hands to the script parser and takes the nodes, tokens, references
// and variables back out of the result.

struct ExprResult {
mut:
	expression Expr
	tokens     []Token
	comments   []Token
	references []Reference
	variables  []Variable
}

fn (c &ExprContext) es_expr(snippet int, node int) Expr {
	if node < 0 {
		return no_expr
	}
	return Expr{
		kind:    .estree
		snippet: snippet
		node:    node
	}
}

// references gives the external references of a fragment (analyzeExternalReferences).
fn (c &ExprContext) references(frag Fragment) []Reference {
	es := c.es(frag.snippet)
	a := analyze_snippet(es)
	return c.to_references(frag, a)
}

fn (c &ExprContext) to_references(frag Fragment, a &Analyzer) []Reference {
	es := c.es(frag.snippet)
	mut out := []Reference{}
	for r in a.external_references() {
		out << Reference{
			id:                 c.es_expr(frag.snippet, r.id)
			name:               es.string_of(r.id, .name) or { '' }
			mode:               if r.flag == ref_read {
				'r'
			} else if r.flag == ref_write {
				'w'
			} else {
				'rw'
			}
			is_value_reference: r.value
			is_type_reference:  r.type_
			has_kind:           true
		}
	}
	return out
}

// variables_and_references is analyzeVariablesAndExternalReferences.
fn (c &ExprContext) variables_and_references(frag Fragment, kind string) ([]Variable, []Reference) {
	es := c.es(frag.snippet)
	a := analyze_snippet(es)
	mut vars := []Variable{}
	for id in a.for_scope_variables() {
		vars << Variable{
			id:   c.es_expr(frag.snippet, id)
			name: a.name_of(id)
			kind: kind
		}
	}
	return vars, c.to_references(frag, a)
}

// adjust is throwErrorAsAdjustingOutsideOfCode: an error past the end of the value is the
// end of the expression.
fn (c &ExprContext) adjust(err IError, code string, calc Calc) IError {
	if err is ParseErr {
		mut perr := err.perr
		end := c.to_bytes(c.doc.offset_with_gap(calc, utf16_length(code)))
		if perr.ts_message && perr.adjust_end < 0 {
			perr.adjust_end = end
		}
		if perr.index >= end {
			// A guess for a TypeScript error (ts_message stays: the real position decides).
			perr.message = 'Unexpected end of expression.'
		}
		return parse_err(perr)
	}
	return err
}

// empty_error is throwEmptyError.
fn (c &ExprContext) empty_error(calc Calc, expected string) IError {
	return parse_err(ParseError{
		message: 'Expected to be ${expected}, but got empty.'
		index:   c.to_bytes(c.doc.offset_with_gap(calc, 0))
	})
}

fn unexpected_token_error(name string, at int) IError {
	return parse_err(ParseError{
		message: "Unexpected token '${name}'."
		index:   at
	})
}

// body0 is the first statement of a fragment's program, or -1.
fn (c &ExprContext) body0(frag Fragment) int {
	es := c.es(frag.snippet)
	body := es.list(frag.root, .body) or { return -1 }
	return if body.len > 0 { body[0] } else { -1 }
}

fn (c &ExprContext) node_of(snippet int, n int, key estree.Key) int {
	if n < 0 {
		return -1
	}
	return c.es(snippet).node(n, key) or { -1 }
}

fn (c &ExprContext) list_of(snippet int, n int, key estree.Key) []int {
	if n < 0 {
		return []int{}
	}
	return c.es(snippet).list(n, key) or { []int{} }
}

// parse_expression_body is parseExpressionBody: `0(code)`.
fn (mut c ExprContext) parse_expression_body(code string, calc Calc, allow_empty bool) !ExprResult {
	return c.parse_expression_body_(code, calc, allow_empty) or { return c.adjust(err, code, calc) }
}

fn (mut c ExprContext) parse_expression_body_(code string, calc Calc, allow_empty bool) !ExprResult {
	frag := c.parse_fragment('0(${code})', c.doc.sub_shift(calc, -2))!
	refs := c.references(frag)
	s := frag.snippet
	call := c.node_of(s, c.body0(frag), .expression)
	args := c.list_of(s, call, .arguments)
	expression := if args.len > 0 { args[0] } else { -1 }
	if !allow_empty && expression < 0 {
		return c.empty_error(calc, 'an expression')
	}
	es := c.es(s)
	if expression >= 0 && es.typ(expression) == .spread_element {
		return unexpected_token_error('...', es.nodes[expression].start)
	}
	if args.len > 1 {
		node := args[1]
		mut index := sorted_index_by_start(frag.tokens, es.nodes[node].start)
		if index >= frag.tokens.len {
			index = frag.tokens.len - 1
		}
		for index >= 0 {
			t := frag.tokens[index]
			if t.typ == 'Punctuator' && t.value == ',' {
				return unexpected_token_error(',', t.start)
			}
			index--
		}
		return unexpected_token_error(',', es.nodes[node].start)
	}
	mut tokens := frag.tokens.clone()
	if tokens.len >= 3 {
		tokens = tokens[2..tokens.len - 1].clone()
	} else {
		tokens = []Token{}
	}
	return ExprResult{
		expression: c.es_expr(s, expression)
		tokens:     tokens
		comments:   frag.comments
		references: refs
	}
}

// parse_expression is parseExpression: an expression, with Vue 2 filters when allowed.
fn (mut c ExprContext) parse_expression(code string, calc Calc, allow_empty bool, allow_filters bool) !ExprResult {
	parts := if allow_filters && c.opts.filter { split_filters(code) } else { [code] }
	if parts.len == 1 {
		return c.parse_expression_body(code, calc, allow_empty)
	}
	main_code := parts[0]
	mut ret := c.parse_expression_body(main_code, calc, false)!
	if ret.expression.is_null() {
		return ret
	}
	inner := ret.expression
	seq := c.doc.add_node(VNode{
		typ:        .v_filter_sequence_expression
		start:      c.expr_start(inner)
		end:        c.expr_end(inner)
		expression: inner
	})
	ret.expression = Expr{
		kind: .vnode
		node: seq
	}
	mut prev := utf16_length(main_code)
	for filter_code in parts[1..] {
		ret.tokens << Token{
			typ:   'Punctuator'
			value: '|'
			start: c.to_bytes(prev + c.doc.fix_offset(calc, prev))
			end:   c.to_bytes(prev + 1 + c.doc.fix_offset(calc, prev + 1))
		}
		f := c.parse_filter(filter_code, c.doc.sub_shift(calc, prev + 1))!
		c.doc.nodes[seq].filters << f.expression.node
		ret.tokens << f.tokens
		ret.comments << f.comments
		ret.references << f.references
		prev += 1 + utf16_length(filter_code)
	}
	c.doc.nodes[seq].end = ret.tokens.last().end
	return ret
}

// expr_start and expr_end are the range of an Expr.
fn (c &ExprContext) expr_start(e Expr) int {
	return match e.kind {
		.null { -1 }
		.estree { c.doc.snippets[e.snippet].es.nodes[e.node].start }
		.vnode { c.doc.nodes[e.node].start }
	}
}

fn (c &ExprContext) expr_end(e Expr) int {
	return match e.kind {
		.null { -1 }
		.estree { c.doc.snippets[e.snippet].es.nodes[e.node].end }
		.vnode { c.doc.nodes[e.node].end }
	}
}

// split_filters is the fork of Vue 2's filter parser: splits at each `|` that is not `||`, not in
// a string, a template, a regular expression or brackets.
fn split_filters(exp string) []string {
	mut result := []string{}
	mut in_single := false
	mut in_double := false
	mut in_template := false
	mut in_regex := false
	mut curly := 0
	mut square := 0
	mut paren := 0
	mut last := 0
	mut c := u8(0)
	mut prev := u8(0)
	for i := 0; i < exp.len; i++ {
		prev = c
		c = exp[i]
		if in_single {
			if c == `'` && prev != `\\` {
				in_single = false
			}
		} else if in_double {
			if c == `"` && prev != `\\` {
				in_double = false
			}
		} else if in_template {
			if c == `\`` && prev != `\\` {
				in_template = false
			}
		} else if in_regex {
			if c == `/` && prev != `\\` {
				in_regex = false
			}
		} else if c == `|` && (i + 1 >= exp.len || exp[i + 1] != `|`)
			&& (i == 0 || exp[i - 1] != `|`) && curly == 0 && square == 0 && paren == 0 {
			result << exp[last..i]
			last = i + 1
		} else {
			match c {
				`"` { in_double = true }
				`'` { in_single = true }
				`\`` { in_template = true }
				`(` { paren++ }
				`)` { paren-- }
				`[` { square++ }
				`]` { square-- }
				`{` { curly++ }
				`}` { curly-- }
				else {}
			}
			if c == `/` {
				mut j := i - 1
				mut p := u8(0)
				mut found := false
				for ; j >= 0; j-- {
					p = exp[j]
					if p != ` ` {
						found = true
						break
					}
				}
				if !found || !(is_word_char(p) || p in [`)`, `.`, `+`, `-`, `$`, `]`]) {
					in_regex = true
				}
			}
		}
	}
	result << exp[last..]
	return result
}

// leading_space_len is the length in bytes of /^\s*/.
fn leading_space_len(s string) int {
	mut i := 0
	for i < s.len {
		cp, n := decode_cp(s, i)
		if !is_js_space(cp) {
			break
		}
		i += n
	}
	return i
}

// parse_filter is parseFilter: `name` or `name(args)`.
fn (mut c ExprContext) parse_filter(code string, calc Calc) !ExprResult {
	return c.parse_filter_(code, calc) or { return c.adjust(err, code, calc) }
}

fn (mut c ExprContext) parse_filter_(code string, calc Calc) !ExprResult {
	paren := code.index_u8(`(`)
	callee_code := if paren < 0 { code } else { code[..paren] }
	trimmed := js_trim(callee_code)
	if trimmed == '' {
		return c.empty_error(calc, 'a filter name')
	}
	filter := c.doc.add_node(VNode{
		typ: .v_filter
	})
	mut tokens := []Token{}
	mut comments := []Token{}
	mut references := []Reference{}
	spaces := leading_space_len(callee_code)
	sub := c.doc.sub_shift(calc, utf16_length(callee_code[..spaces]))
	frag := c.parse_fragment('"${trimmed}"', sub)!
	es := c.es(frag.snippet)
	callee := c.node_of(frag.snippet, c.body0(frag), .expression)
	if callee < 0 || es.typ(callee) != .literal {
		t := frag.tokens[0]
		return unexpected_token_error('"', t.end - 1)
	}
	name := es.string_of(callee, .value) or { '' }
	start := es.nodes[callee].start
	end := c.to_bytes(c.doc.offset_with_gap(sub, utf16_length(trimmed)))
	c.doc.nodes[filter].callee_name = name
	c.doc.nodes[filter].callee_start = start
	c.doc.nodes[filter].callee_end = end
	tokens << Token{
		typ:   'Identifier'
		value: trimmed
		start: start
		end:   end
	}
	if paren >= 0 {
		args_code := code[paren..]
		args_calc := c.doc.sub_shift(c.doc.sub_after(calc, utf16_length(code[..paren])), -1)
		frag2 := c.parse_fragment('0${args_code}', args_calc)!
		es2 := c.es(frag2.snippet)
		call := c.node_of(frag2.snippet, c.body0(frag2), .expression)
		ast_tokens := if frag2.tokens.len > 0 { frag2.tokens[1..] } else { []Token{} }
		if call < 0 || es2.typ(call) != .call_expression
			|| es2.typ(c.node_of(frag2.snippet, call, .callee)) != .literal {
			mut nest := 1
			for i in 1 .. ast_tokens.len {
				t := ast_tokens[i]
				if nest == 0 {
					return unexpected_token_error(t.value, t.start)
				}
				if t.typ == 'Punctuator' && t.value == '(' {
					nest++
				}
				if t.typ == 'Punctuator' && t.value == ')' {
					nest--
				}
			}
			t := ast_tokens.last()
			return unexpected_token_error(t.value, t.start)
		}
		for arg in c.list_of(frag2.snippet, call, .arguments) {
			c.doc.nodes[filter].exprs << c.es_expr(frag2.snippet, arg)
		}
		tokens << ast_tokens
		comments << frag2.comments
		references << c.references(frag2)
	}
	c.doc.nodes[filter].start = tokens[0].start
	c.doc.nodes[filter].end = tokens.last().end
	return ExprResult{
		expression: Expr{
			kind: .vnode
			node: filter
		}
		tokens:     tokens
		comments:   comments
		references: references
	}
}

// VForParts is processVForAliasAndIterator's result.
struct VForParts {
	aliases               string
	has_parens            bool
	delimiter             string
	iterator              string
	aliases_with_brackets string
}

// ends_with_space_or_paren: the code point that ends at `end` is `\s` or `)`.
fn ends_with_space_or_paren(s string, end int) bool {
	if end <= 0 {
		return false
	}
	if s[end - 1] == `)` {
		return true
	}
	mut start := end - 1
	for start > 0 && (s[start] & 0xc0) == 0x80 {
		start--
	}
	cp, _ := decode_cp(s, start)
	return is_js_space(cp)
}

// process_v_for is processVForAliasAndIterator with
// ALIAS_ITERATOR = /^([\s\S]*?(?:\s|\)))(\bin\b|\bof\b)([\s\S]*)$/u and
// PARENS = /^(\s*\()([\s\S]*?)(\)\s*)$/u.
fn process_v_for(code string) VForParts {
	for i := 1; i + 2 <= code.len; i++ {
		if (code[i] & 0xc0) == 0x80 {
			continue
		}
		if !ends_with_space_or_paren(code, i) {
			continue
		}
		word := code[i..i + 2]
		if word != 'in' && word != 'of' {
			continue
		}
		if i + 2 < code.len && (is_word_char(code[i + 2])) {
			continue
		}
		aliases := code[..i]
		// PARENS
		lead := leading_space_len(aliases)
		mut with_brackets := ''
		mut has_parens := false
		if lead < aliases.len && aliases[lead] == `(` {
			// The `)` is the last one: only white space may follow it.
			trailing := js_trim_end(aliases)
			if trailing.ends_with(')') {
				has_parens = true
				close := trailing.len - 1
				with_brackets = aliases[..lead] + '[' + aliases[lead + 1..close] + ']' +
					aliases[close + 1..]
			}
		}
		if !has_parens {
			mut cut := aliases.len - 1
			for cut > 0 && (aliases[cut] & 0xc0) == 0x80 {
				cut--
			}
			with_brackets = '[' + aliases[..cut] + ']'
		}
		return VForParts{
			aliases:               aliases
			has_parens:            has_parens
			delimiter:             word
			iterator:              code[i + 2..]
			aliases_with_brackets: with_brackets
		}
	}
	return VForParts{
		iterator: code
	}
}

// parse_v_for is parseVForExpression: `for(let [aliases] in iterator);`.
fn (mut c ExprContext) parse_v_for(code string, calc Calc) !ExprResult {
	if js_trim(code) == '' {
		return c.empty_error(calc, "'<alias> in <expression>'")
	}
	p := process_v_for(code)
	if js_trim(p.aliases) == '' {
		return c.empty_error(calc, 'an alias')
	}
	return c.parse_v_for_(calc, p) or { return c.adjust(err, code, calc) }
}

fn (mut c ExprContext) parse_v_for_(calc Calc, p VForParts) !ExprResult {
	frag := c.parse_fragment('for(let ${p.aliases_with_brackets}${p.delimiter}${p.iterator});',
		c.doc.sub_shift(calc, if p.has_parens { -8 } else { -9 }))!
	vars, refs := c.variables_and_references(frag, 'v-for')
	s := frag.snippet
	es := c.es(s)
	statement := c.body0(frag)
	var_decl := c.node_of(s, statement, .left)
	decls := c.list_of(s, var_decl, .declarations)
	id := if decls.len > 0 { c.node_of(s, decls[0], .id) } else { -1 }
	left := c.list_of(s, id, .elements)
	right := c.node_of(s, statement, .right)
	if !p.has_parens && left.len == 0 {
		return c.empty_error(calc, 'an alias')
	}
	mut tokens := frag.tokens.clone()
	tokens = if tokens.len >= 5 { tokens[3..tokens.len - 2].clone() } else { []Token{} }
	close_offset := es.nodes[var_decl].end - 1
	mut close_index := -1
	for i, t in tokens {
		if t.start == close_offset {
			close_index = i
			break
		}
	}
	if p.has_parens {
		if tokens.len > 0 {
			tokens[0].value = '('
		}
		if close_index >= 0 {
			tokens[close_index].value = ')'
		}
	} else {
		// splice(-1, 1) removes the last token when the bracket is not found.
		ci := if close_index < 0 { tokens.len - 1 } else { close_index }
		if ci >= 0 && ci < tokens.len {
			tokens.delete(ci)
		}
		if tokens.len > 0 {
			tokens.delete(0)
		}
	}
	start := if tokens.len > 0 { tokens[0].start } else { es.nodes[var_decl].start }
	end := if tokens.len > 0 { tokens.last().end } else { es.nodes[right].end }
	mut exprs := []Expr{}
	for l in left {
		exprs << c.es_expr(s, l)
	}
	node := c.doc.add_node(VNode{
		typ:   .v_for_expression
		start: start
		end:   end
		exprs: exprs
		right: c.es_expr(s, right)
	})
	return ExprResult{
		expression: Expr{
			kind: .vnode
			node: node
		}
		tokens:     tokens
		comments:   frag.comments
		references: refs
		variables:  vars
	}
}

// is_function_expression is IS_FUNCTION_EXPRESSION =
// /^\s*([\w$_]+|(async\s*)?\([^)]*?\))\s*(:[^=]+)?=>|^\s*(async\s+)?function(?:\s+[\w$]+)?\s*\(/u.
fn is_function_expression(code string) bool {
	s := code[leading_space_len(code)..]
	// An arrow function: a name or a parenthesized list, then `=>` (maybe after a return type).
	mut word := 0
	for word < s.len && (is_word_char(s[word]) || s[word] == `$`) {
		word++
	}
	if word > 0 && arrow_after(s[word..]) {
		return true
	}
	if s.starts_with('async') {
		mut i := 5
		for i < s.len {
			cp, n := decode_cp(s, i)
			if !is_js_space(cp) {
				break
			}
			i += n
		}
		if i < s.len && s[i] == `(` && paren_arrow(s[i..]) {
			return true
		}
	}
	if s.len > 0 && s[0] == `(` && paren_arrow(s) {
		return true
	}
	// A function expression.
	mut f := s
	if s.starts_with('async') {
		rest := s[5..]
		sp := leading_space_len(rest)
		if sp == 0 {
			return false
		}
		f = rest[sp..]
	}
	if !f.starts_with('function') {
		return false
	}
	mut r := f[8..]
	sp := leading_space_len(r)
	if sp > 0 {
		r = r[sp..]
		mut w := 0
		for w < r.len && (is_word_char(r[w]) || r[w] == `$`) {
			w++
		}
		r = r[w..]
		r = r[leading_space_len(r)..]
	}
	return r.len > 0 && r[0] == `(`
}

// paren_arrow: `(` up to the first `)`, then an arrow.
fn paren_arrow(s string) bool {
	close := s.index_u8(`)`)
	if close < 0 {
		return false
	}
	return arrow_after(s[close + 1..])
}

// arrow_after is /^\s*(:[^=]+)?=>/.
fn arrow_after(s_ string) bool {
	s := s_[leading_space_len(s_)..]
	if s.starts_with('=>') {
		return true
	}
	if s.len > 0 && s[0] == `:` {
		eq := s.index_u8(`=`)
		return eq > 1 && eq + 1 < s.len && s[eq + 1] == `>`
	}
	return false
}

fn is_ident_start(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || c == `_` || c == `$`
}

// is_simple_path is IS_SIMPLE_PATH = /^[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*|\['[^']*?'\]|
// \["[^"]*?"\]|\[\d+\]|\[[A-Za-z_$][\w$]*\])*$/u.
fn is_simple_path(s string) bool {
	if s.len == 0 || !is_ident_start(s[0]) {
		return false
	}
	mut i := 1
	for i < s.len && (is_word_char(s[i]) || s[i] == `$`) {
		i++
	}
	for i < s.len {
		if s[i] == `.` {
			i++
			if i >= s.len || !is_ident_start(s[i]) {
				return false
			}
			i++
			for i < s.len && (is_word_char(s[i]) || s[i] == `$`) {
				i++
			}
			continue
		}
		if s[i] != `[` || i + 1 >= s.len {
			return false
		}
		q := s[i + 1]
		if q == `'` || q == `"` {
			close := s.index_after_(q.ascii_str() + ']', i + 2)
			if close < 0 {
				return false
			}
			// The content cannot hold the quote.
			if s[i + 2..close].contains(q.ascii_str()) {
				return false
			}
			i = close + 2
			continue
		}
		if q >= `0` && q <= `9` {
			mut j := i + 1
			for j < s.len && s[j] >= `0` && s[j] <= `9` {
				j++
			}
			if j >= s.len || s[j] != `]` {
				return false
			}
			i = j + 1
			continue
		}
		if is_ident_start(q) {
			mut j := i + 2
			for j < s.len && (is_word_char(s[j]) || s[j] == `$`) {
				j++
			}
			if j >= s.len || s[j] != `]` {
				return false
			}
			i = j + 1
			continue
		}
		return false
	}
	return true
}

// parse_v_on is parseVOnExpression.
fn (mut c ExprContext) parse_v_on(code string, calc Calc) !ExprResult {
	if is_function_expression(code) || is_simple_path(code) {
		return c.parse_expression_body(code, calc, false)
	}
	if js_trim(code) == '' {
		return c.empty_error(calc, 'statements')
	}
	return c.parse_v_on_body(code, calc) or { return c.adjust(err, code, calc) }
}

fn (mut c ExprContext) parse_v_on_body(code string, calc Calc) !ExprResult {
	frag := c.parse_fragment('void function(\$event){${code}}', c.doc.sub_shift(calc, -22))!
	refs := c.references(frag)
	s := frag.snippet
	es := c.es(s)
	unary := c.node_of(s, c.body0(frag), .expression)
	func := c.node_of(s, unary, .argument)
	block := c.node_of(s, func, .body)
	body := c.list_of(s, block, .body)
	mut start := 0
	mut end := 0
	mut loc_start := -1
	mut loc_end := -1
	if body.len > 0 {
		start = es.nodes[body[0]].start
	} else {
		start = c.to_bytes(c.doc.utf16(es.nodes[block].start) + 1)
		loc_start = c.to_bytes(c.doc.offset_with_gap(calc, 1))
	}
	if body.len > 0 {
		end = es.nodes[body.last()].end
	} else {
		end = c.to_bytes(c.doc.utf16(es.nodes[block].end) - 1)
		loc_end = c.to_bytes(c.doc.offset_with_gap(calc, utf16_length(code) + 1))
	}
	mut exprs := []Expr{}
	for b in body {
		exprs << c.es_expr(s, b)
	}
	node := c.doc.add_node(VNode{
		typ:       .v_on_expression
		start:     start
		end:       end
		loc_start: loc_start
		loc_end:   loc_end
		exprs:     exprs
	})
	mut tokens := frag.tokens.clone()
	tokens = if tokens.len >= 7 { tokens[6..tokens.len - 1].clone() } else { []Token{} }
	return ExprResult{
		expression: Expr{
			kind: .vnode
			node: node
		}
		tokens:     tokens
		comments:   frag.comments
		references: refs
	}
}

// parse_slot_scope is parseSlotScopeExpression: `void function(code) {}`.
fn (mut c ExprContext) parse_slot_scope(code string, calc Calc) !ExprResult {
	if js_trim(code) == '' {
		return c.empty_error(calc, 'an identifier or an array/object pattern')
	}
	return c.parse_slot_scope_(code, calc) or { return c.adjust(err, code, calc) }
}

fn (mut c ExprContext) parse_slot_scope_(code string, calc Calc) !ExprResult {
	frag := c.parse_fragment('void function(${code}) {}', c.doc.sub_shift(calc, -14))!
	s := frag.snippet
	es := c.es(s)
	unary := c.node_of(s, c.body0(frag), .expression)
	func := c.node_of(s, unary, .argument)
	params := c.list_of(s, func, .params)
	if params.len == 0 {
		return ExprResult{}
	}
	vars, refs := c.variables_and_references(frag, 'scope')
	mut exprs := []Expr{}
	for p in params {
		exprs << c.es_expr(s, p)
	}
	node := c.doc.add_node(VNode{
		typ:   .v_slot_scope_expression
		start: es.nodes[params[0]].start
		end:   es.nodes[params.last()].end
		exprs: exprs
	})
	mut tokens := frag.tokens.clone()
	tokens = if tokens.len >= 6 { tokens[3..tokens.len - 3].clone() } else { []Token{} }
	return ExprResult{
		expression: Expr{
			kind: .vnode
			node: node
		}
		tokens:     tokens
		comments:   frag.comments
		references: refs
		variables:  vars
	}
}

// parse_generic is parseGenericExpression: `void function<code>(){}`.
fn (mut c ExprContext) parse_generic(code string, calc Calc) !ExprResult {
	if js_trim(code) == '' {
		return c.empty_error(calc, 'a type parameter')
	}
	return c.parse_generic_(code, calc) or { return c.adjust(err, code, calc) }
}

fn (mut c ExprContext) parse_generic_(code string, calc Calc) !ExprResult {
	script_let := 'void function<${code}>(){}'
	frag := c.parse_fragment(script_let, c.doc.sub_shift(calc, -14))!
	s := frag.snippet
	es := c.es(s)
	unary := c.node_of(s, c.body0(frag), .expression)
	func := c.node_of(s, unary, .argument)
	tps := c.node_of(s, func, .type_parameters)
	params := c.list_of(s, tps, .params)
	if params.len == 0 {
		return ExprResult{}
	}
	mut raw_params := []string{}
	for p in params {
		raw_params << script_let[frag.snip_start[p]..frag.snip_end[p]]
	}
	vars, refs := c.variables_and_references(frag, 'generic')
	mut exprs := []Expr{}
	for p in params {
		exprs << c.es_expr(s, p)
	}
	node := c.doc.add_node(VNode{
		typ:        .v_generic_expression
		start:      es.nodes[params[0]].start
		end:        es.nodes[params.last()].end
		exprs:      exprs
		raw_params: raw_params
	})
	mut tokens := frag.tokens.clone()
	tokens = if tokens.len >= 8 { tokens[3..tokens.len - 5].clone() } else { []Token{} }
	return ExprResult{
		expression: Expr{
			kind: .vnode
			node: node
		}
		tokens:     tokens
		comments:   frag.comments
		references: refs
		variables:  vars
	}
}
