module svelte_compiler

// The checks acorn makes while parsing that typescript-eslint's parser (what svelte-eslint-parser
// uses) does not: redeclarations (acorn's scope tracking, module code: strict), a comma after a
// rest element, and keywords as binding names. They are parse errors of compile()
// (js_parse_error).

const scope_top = 1
const scope_function = 2
const scope_arrow = 16
const scope_simple_catch = 32
const scope_class_static_block = 256
const scope_var = scope_top | scope_function | scope_class_static_block

const bind_var = 1
const bind_lexical = 2
const bind_function = 3
const bind_simple_catch = 4

struct AcornScope {
	flags int
mut:
	var_      []string
	lexical   []string
	functions []string
}

struct AcornChecker {
mut:
	t      &Tree
	scopes []AcornScope
	err    ?CompileError
}

fn (c &AcornChecker) treat_functions_as_var_in(s AcornScope) bool {
	// Module code: only function scopes treat function declarations as var.
	return s.flags & scope_function != 0
}

fn (mut c AcornChecker) declare(id int, binding int) {
	if c.err != none || id < 0 {
		return
	}
	name := c.t.name(id)
	mut redeclared := false
	top := c.scopes.len - 1
	match binding {
		bind_lexical {
			s := c.scopes[top]
			redeclared = name in s.lexical || name in s.functions || name in s.var_
			c.scopes[top].lexical << name
		}
		bind_simple_catch {
			c.scopes[top].lexical << name
		}
		bind_function {
			s := c.scopes[top]
			redeclared = if c.treat_functions_as_var_in(s) {
				name in s.lexical
			} else {
				name in s.lexical || name in s.var_
			}
			c.scopes[top].functions << name
		}
		else {
			for i := top; i >= 0; i-- {
				s := c.scopes[i]
				if (name in s.lexical && !(s.flags & scope_simple_catch != 0 && s.lexical[0] == name))
					|| (!c.treat_functions_as_var_in(s) && name in s.functions) {
					redeclared = true
					break
				}
				c.scopes[i].var_ << name
				if s.flags & scope_var != 0 {
					break
				}
			}
		}
	}
	if redeclared {
		start := c.t.nodes[id].start
		c.err = CompileError{
			diag:  e_js_parse_error("Identifier '${name}' has already been declared")
			start: start
			end:   start
		}
	}
}

fn (mut c AcornChecker) declare_pattern(pattern int, binding int) {
	for id in c.t.extract_identifiers(pattern) {
		c.declare(id, binding)
	}
}

// check_redeclarations runs acorn's checks on a parse unit (a script's Program, or a template
// expression): the first redeclaration, if any.
fn check_redeclarations(t &Tree, root int) ?CompileError {
	mut c := AcornChecker{
		t: unsafe { t }
	}
	c.scopes << AcornScope{
		flags: scope_top
	}
	c.visit(root)
	return c.err
}

fn (mut c AcornChecker) push(flags int) {
	c.scopes << AcornScope{
		flags: flags
	}
}

fn (mut c AcornChecker) pop() {
	c.scopes.pop()
}

fn (mut c AcornChecker) visit_all(nodes []int) {
	for n in nodes {
		c.visit(n)
	}
}

// visit_function: params in a new function scope, the body's statements in it too.
fn (mut c AcornChecker) visit_function(node int, flags int) {
	t := c.t
	c.push(flags)
	for p in t.list(node, .params) {
		c.declare_pattern(p, bind_var)
	}
	c.visit_all(t.list(node, .params))
	body := t.get(node, .body)
	if t.typ(body) == 'BlockStatement' {
		c.visit_all(t.list(body, .body))
	} else {
		c.visit(body)
	}
	c.pop()
}

fn (mut c AcornChecker) visit(node int) {
	if node < 0 || c.err != none {
		return
	}
	t := c.t
	match t.typ(node) {
		'Program' {
			c.visit_all(t.list(node, .body))
		}
		'FunctionDeclaration' {
			id := t.get(node, .id)
			if id >= 0 {
				top := c.scopes[c.scopes.len - 1]
				c.declare(id, if c.treat_functions_as_var_in(top) { bind_var } else { bind_lexical })
			}
			c.visit_function(node, scope_function)
		}
		'FunctionExpression' {
			c.visit_function(node, scope_function)
		}
		'ArrowFunctionExpression' {
			c.visit_function(node, scope_function | scope_arrow)
		}
		'BlockStatement' {
			c.push(0)
			c.visit_all(t.list(node, .body))
			c.pop()
		}
		'StaticBlock' {
			c.push(scope_class_static_block)
			c.visit_all(t.list(node, .body))
			c.pop()
		}
		'VariableDeclaration' {
			kind := if t.text(node, .kind) == 'var' { bind_var } else { bind_lexical }
			for d in t.list(node, .declarations) {
				c.declare_pattern(t.get(d, .id), kind)
				c.visit(t.get(d, .id))
				c.visit(t.get(d, .init))
			}
		}
		'ClassDeclaration' {
			c.declare(t.get(node, .id), bind_lexical)
			c.visit(t.get(node, .super_class))
			c.visit(t.get(node, .body))
		}
		'ImportDeclaration' {
			for s in t.list(node, .specifiers) {
				c.declare(t.get(s, .local), bind_lexical)
			}
		}
		'CatchClause' {
			param := t.get(node, .param)
			if t.typ(param) == 'Identifier' {
				c.push(scope_simple_catch)
				c.declare(param, bind_simple_catch)
			} else {
				c.push(0)
				if param >= 0 {
					c.declare_pattern(param, bind_lexical)
					c.visit(param)
				}
			}
			c.visit_all(t.list(t.get(node, .body), .body))
			c.pop()
		}
		'ForStatement', 'ForInStatement', 'ForOfStatement' {
			c.push(0)
			for ch in t.children(node) {
				c.visit(ch)
			}
			c.pop()
		}
		'AssignmentExpression', 'UpdateExpression' {
			// acorn's toAssignable / checkLValSimple: what typescript-eslint's parser lets through.
			target := t.get(node, if t.typ(node) == 'UpdateExpression' {
				Key.argument
			} else {
				Key.left
			})
			mut ok := t.typ(target) in ['Identifier', 'MemberExpression']
			if t.typ(node) == 'AssignmentExpression' && t.text(node, .operator) == '=' {
				ok = ok || t.typ(target) in ['ObjectPattern', 'ArrayPattern']
			}
			if !ok && c.err == none && t.nodes[target].start != no_pos {
				start := t.nodes[target].start
				c.err = CompileError{
					diag:  e_js_parse_error('Assigning to rvalue')
					start: start
					end:   start
				}
			}
			for ch in t.children(node) {
				c.visit(ch)
			}
		}
		'SwitchStatement' {
			c.visit(t.get(node, .discriminant))
			c.push(0)
			c.visit_all(t.list(node, .cases))
			c.pop()
		}
		else {
			for ch in t.children(node) {
				c.visit(ch)
			}
		}
	}
}

// ---------------------------------------------------------------------------------------------

const js_keywords = ['break', 'case', 'catch', 'continue', 'debugger', 'default', 'do', 'else',
	'finally', 'for', 'function', 'if', 'return', 'switch', 'throw', 'try', 'var', 'while', 'with',
	'null', 'true', 'false', 'instanceof', 'typeof', 'void', 'delete', 'new', 'in', 'this', 'const',
	'class', 'extends', 'export', 'import', 'super']

// check_pattern: a binding pattern of the template (each context, snippet parameters…) as acorn
// parses it: no comma after a rest element, no keyword as a name.
fn (b &Builder) check_pattern(pattern int) ?CompileError {
	t := &b.c.t
	src := b.c.src
	typ := t.typ(pattern)
	if typ == 'Identifier' {
		if t.name(pattern) in js_keywords {
			// The compiler parses `(pattern = 1)` as an expression first: a keyword is an
			// unexpected token, but a shorthand property `{ case }` an unexpected keyword.
			start := t.nodes[pattern].start
			mut shorthand := false
			for k := b.c.t.nodes.len - 1; k >= 0 && !shorthand; k-- {
				if t.typ(k) == 'Property' && t.flag(k, .shorthand) && t.get(k, .value) == pattern {
					shorthand = true
				}
			}
			return CompileError{
				diag:  e_js_parse_error(if shorthand {
					"Unexpected keyword '${t.name(pattern)}'"
				} else {
					'Unexpected token'
				})
				start: start
				end:   start
			}
		}
		return none
	}
	items := if typ == 'ObjectPattern' {
		t.list(pattern, .properties)
	} else if typ == 'ArrayPattern' {
		t.list(pattern, .elements)
	} else {
		[]int{}
	}
	for k, item in items {
		if item < 0 {
			continue
		}
		if t.typ(item) == 'RestElement' && k < items.len - 1 {
			// acorn raises at the comma after the rest element.
			mut i := t.nodes[item].end
			for i < src.len && src[i] in [` `, `\t`, `\n`, `\r`] {
				i++
			}
			return CompileError{
				diag:  e_js_parse_error('Comma is not permitted after the rest element')
				start: i
				end:   i
			}
		}
		if t.typ(item) == 'RestElement' && k == items.len - 1 {
			mut i := t.nodes[item].end
			for i < src.len && src[i] in [` `, `\t`, `\n`, `\r`] {
				i++
			}
			if i < src.len && src[i] == `,` {
				return CompileError{
					diag:  e_js_parse_error('Comma is not permitted after the rest element')
					start: i
					end:   i
				}
			}
		}
		sub := match t.typ(item) {
			'Property' { t.get(item, .value) }
			'RestElement' { t.get(item, .argument) }
			else { item }
		}
		if e := b.check_pattern(sub) {
			return e
		}
	}
	if typ in ['AssignmentPattern', 'RestElement'] {
		for ch in t.children(pattern) {
			if ch == t.get(pattern, .right) {
				continue
			}
			if e := b.check_pattern(ch) {
				return e
			}
		}
	}
	return none
}
