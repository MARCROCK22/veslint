module svelte_compiler

// What TypeScript's transpileModule does to a script for an ES5 target that changes what the
// compiler says of it: `let` and `const` become `var`, and a destructuring declaration becomes
// plain declarators (flattenDestructuringBinding, FlattenLevel.All): `let { a } = f()` is
// `var a = f().a`, `let { a, b } = f()` is `var _a = f(), a = _a.a, b = _a.b`, a default value
// `let { a = 1 } = f()` is `var _a = f().a, a = _a === void 0 ? 1 : _a`. The nodes TypeScript
// makes have no position. Template expressions are not transpiled.

fn (mut b Builder) es5_declaration(decl int) {
	b.c.t.set_str(decl, .kind, 'var')
	mut out := []int{}
	for d in b.c.t.list(decl, .declarations) {
		id := b.c.t.get(d, .id)
		if b.c.t.typ(id) !in ['ObjectPattern', 'ArrayPattern'] {
			out << d
			continue
		}
		b.es5_flatten(id, b.c.t.get(d, .init), true, mut out)
	}
	b.c.t.set_list(decl, .declarations, out)
}

// es5_temp makes a temporary (`_a`, `_b`… as TypeScript names them, skipping the names the file
// has).
fn (mut b Builder) es5_temp() string {
	for {
		k := b.es5_temps
		b.es5_temps++
		name := '_' + if k < 26 { u8(`a` + k).ascii_str() } else { 'a${k}' }
		if !b.c.src.contains(name) {
			return name
		}
	}
	return ''
}

fn (mut b Builder) es5_id(name string) int {
	return b.c.t.id(name)
}

fn (mut b Builder) es5_declarator(id int, init int, mut out []int) {
	d := b.c.t.new_node('VariableDeclarator', no_pos, no_pos)
	b.c.t.set_node(d, .id, id)
	b.c.t.set_node(d, .init, init)
	out << d
}

// es5_ensure_identifier: the value itself when an identifier (and `reuse`), else a temporary
// declared with it.
fn (mut b Builder) es5_ensure_identifier(value int, reuse bool, mut out []int) int {
	if b.c.t.typ(value) == 'Identifier' && reuse {
		return value
	}
	name := b.es5_temp()
	b.es5_declarator(b.es5_id(name), value, mut out)
	return b.es5_id(name)
}

fn (mut b Builder) es5_member(object int, property int, computed bool) int {
	m := b.c.t.new_node('MemberExpression', no_pos, no_pos)
	b.c.t.set_node(m, .object, object)
	b.c.t.set_node(m, .property, property)
	b.c.t.set_flag(m, .computed, computed)
	b.c.t.set_flag(m, .optional, false)
	return m
}

fn (mut b Builder) es5_number(n int) int {
	l := b.c.t.new_node('Literal', no_pos, no_pos)
	b.c.t.set(l, P{
		key:  .value
		kind: .num
		n:    n
	})
	b.c.t.set_str(l, .raw, n.str())
	return l
}

// es5_copy is a copy of an identifier or literal key without position.
fn (mut b Builder) es5_copy(node int) int {
	i := b.c.t.new_node(b.c.t.typ(node), no_pos, no_pos)
	b.c.t.nodes[i].props = b.c.t.nodes[node].props.clone()
	return i
}

// es5_flatten flattens `target = value` (flattenBindingOrAssignmentElement).
fn (mut b Builder) es5_flatten(target int, value_in int, in_declaration bool, mut out []int) {
	t := &b.c.t
	mut value := value_in
	mut tgt := target
	if t.typ(tgt) == 'AssignmentPattern' {
		initializer := t.get(tgt, .right)
		tgt = t.get(tgt, .left)
		if value >= 0 {
			v := b.es5_ensure_identifier(value, true, mut out)
			test := b.c.t.new_node('BinaryExpression', no_pos, no_pos)
			b.c.t.set_node(test, .left, v)
			b.c.t.set_str(test, .operator, '===')
			void0 := b.c.t.new_node('UnaryExpression', no_pos, no_pos)
			b.c.t.set_str(void0, .operator, 'void')
			b.c.t.set_flag(void0, .prefix, true)
			b.c.t.set_node(void0, .argument, b.es5_number(0))
			b.c.t.set_node(test, .right, void0)
			cond := b.c.t.new_node('ConditionalExpression', no_pos, no_pos)
			b.c.t.set_node(cond, .test, test)
			b.c.t.set_node(cond, .consequent, initializer)
			b.c.t.set_node(cond, .alternate, b.es5_id(b.c.t.name(v)))
			value = cond
		} else {
			value = initializer
		}
	}
	match t.typ(tgt) {
		'ObjectPattern' {
			elements := t.list(tgt, .properties)
			if elements.len != 1 && value >= 0 {
				value = b.es5_ensure_identifier(value, !in_declaration || elements.len != 0, mut
					out)
			}
			for el in elements {
				if t.typ(el) == 'RestElement' {
					// __rest(value, [...]): a call of a helper.
					call := b.c.t.new_node('CallExpression', no_pos, no_pos)
					b.c.t.set_node(call, .callee, b.es5_id('__rest'))
					b.c.t.set_list(call, .arguments, [b.es5_id(b.c.t.name(value))])
					b.es5_flatten(t.get(el, .argument), call, in_declaration, mut out)
					continue
				}
				key := t.get(el, .key)
				computed := t.flag(el, .computed) || t.typ(key) != 'Identifier'
				obj := if t.typ(value) == 'Identifier' { b.es5_id(t.name(value)) } else { value }
				rhs := b.es5_member(obj, b.es5_copy(key), computed)
				b.es5_flatten(t.get(el, .value), rhs, in_declaration, mut out)
			}
		}
		'ArrayPattern' {
			elements := t.list(tgt, .elements)
			if (elements.len != 1 || elements.all(it < 0)) && value >= 0 {
				value = b.es5_ensure_identifier(value, !in_declaration || elements.len != 0, mut
					out)
			}
			for i, el in elements {
				if el < 0 {
					continue
				}
				obj := if t.typ(value) == 'Identifier' { b.es5_id(t.name(value)) } else { value }
				if t.typ(el) == 'RestElement' {
					slice := b.es5_member(obj, b.es5_id('slice'), false)
					call := b.c.t.new_node('CallExpression', no_pos, no_pos)
					b.c.t.set_node(call, .callee, slice)
					b.c.t.set_list(call, .arguments, [b.es5_number(i)])
					b.es5_flatten(t.get(el, .argument), call, in_declaration, mut out)
					continue
				}
				b.es5_flatten(el, b.es5_member(obj, b.es5_number(i), true), in_declaration, mut
					out)
			}
		}
		else {
			b.es5_declarator(tgt, value, mut out)
		}
	}
}
