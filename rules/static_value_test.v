module rules

import json2
import math
import os
import treesitter { first_named_child, named_children, node_kind, nodes_of_kind, position_of, root_node, token_ends }

// The expected values come from tools/gen_static_value_cases.mjs: what getStaticValue of
// @eslint-community/eslint-utils gives, in ESLint, for each expression statement of a source
// (tests/static_value_cases.json). The names below were computed with ESLint 10.6.0:
// getStaticMemberAccessValue / getPropertyName of member expression statements.

const stv_test_names_source = "const key = 'reduce';\nconst index = 0;\nlet counter = 1;\ncounter++;\ndeclare const o: Record<string, number>;\no.reduce;\no['reduce'];\no[`reduce`];\no['re' + 'duce'];\no[key];\no[index];\no[counter];\no[0];\no[1.50];\no[0x10];\no[1n];\no[null];\no[true];\no[undefined];\no[[1, 2]];\no[{}];\no[/a/g];\no[Symbol.iterator];\no[`a\${key}`];\no[unknown];\no.#private;\no?.reduce;\no?.['reduce'];\n"

// Line of the member expression statement, getStaticMemberAccessValue and getPropertyName.
const stv_test_names_expected = [
	'6	"reduce"	"reduce"',
	'7	"reduce"	"reduce"',
	'8	"reduce"	"reduce"',
	'9	"reduce"	"reduce"',
	'10	"reduce"	"reduce"',
	'11	"0"	"0"',
	'12	undefined	null',
	'13	"0"	"0"',
	'14	"1.5"	"1.5"',
	'15	"16"	"16"',
	'16	"1"	"1"',
	'17	"null"	"null"',
	'18	"true"	"true"',
	'19	"undefined"	"undefined"',
	'20	"1,2"	"1,2"',
	'21	"[object Object]"	"[object Object]"',
	'22	"/a/g"	"/a/g"',
	'23	symbol	"Symbol(Symbol.iterator)"',
	'24	"areduce"	"areduce"',
	'25	undefined	null',
	'26	"private"	null',
]

fn stv_test_hex(units []u16) string {
	return units.map(u32(it).hex()).join(',')
}

fn stv_test_number(x f64) string {
	return if x == 0 && math.signbit(x) {
		'-0'
	} else if math.is_inf(x, -1) {
		'-Infinity'
	} else {
		js_number_to_string(x)
	}
}

// stv_test_serialize writes a value like `serialize` of tools/gen_static_value_cases.mjs:
// u(ndefined), null, b(oolean), n(umber), s(tring, as UTF-16 units), i (BigInt), y (a well-known
// symbol), f (a builtin function) or ns (another builtin object) with its name, a[…] (array, h:
// a hole), o{…} (object), r (RegExp), m{…} (Map), e[…] (Set) and t (an iterator, with what is
// left of it).
fn stv_test_serialize(v JsAny, depth int) string {
	if depth > 6 {
		return '…'
	}
	return match v.kind {
		.undefined_ {
			'u'
		}
		.hole_ {
			'h'
		}
		.null_ {
			'null'
		}
		.boolean_ {
			'b:${v.boolean}'
		}
		.number_ {
			'n:' + stv_test_number(v.number)
		}
		.string_ {
			's:' + stv_test_hex(v.units)
		}
		.bigint_ {
			'i:' + v.digits
		}
		.symbol_ {
			if v.registered { 'yr:' + stv_test_hex(v.units) } else { 'y:' + v.name }
		}
		.wrapper_ {
			'w(' + stv_test_serialize(v.elements[0], depth + 1) + ')'
		}
		.function_ {
			'f:' + v.name
		}
		.array_ {
			'a[' + v.elements.map(stv_test_serialize(it, depth + 1)).join(';') + ']'
		}
		.regexp_ {
			'r:' + stv_test_hex(v.regexp.source) + '/' + v.regexp.flags
		}
		.namespace_ {
			'ns:' + v.name
		}
		.object_ {
			mut parts := []string{}
			for i, k in v.keys {
				parts << stv_test_hex(stv_key_units(k)) + '=' + stv_test_serialize(v.values[i], depth + 1)
			}
			prototype := if v.elements.len == 0 {
				''
			} else if v.elements[0].kind == .null_ {
				'^null'
			} else {
				'^' + stv_test_serialize(v.elements[0], depth + 1)
			}
			'o' + prototype + '{' + parts.join(';') + '}'
		}
		.map_ {
			mut parts := []string{}
			for i, k in v.elements {
				parts << stv_test_serialize(k, depth + 1) + '=>' +
					stv_test_serialize(v.values[i], depth + 1)
			}
			'm{' + parts.join(';') + '}'
		}
		.set_ {
			'e[' + v.elements.map(stv_test_serialize(it, depth + 1)).join(';') + ']'
		}
		.iterator_ {
			't:${v.name}[' + v.elements.map(stv_test_serialize(it, depth + 1)).join(';') + ']'
		}
	}
}

fn stv_test_checker(src string) (Checker, C.TSNode) {
	parser := treesitter.new_parser() or { panic(err) }
	tree := parser.parse(src) or { panic(err) }
	root := root_node(tree)
	return Checker{
		src:    src
		tokens: token_ends(root)
	}, root
}

// stv_test_max_steps bounds the sub-expressions one evaluation may visit in these tests. The
// longest one of tests/static_value_cases.json visits a few hundred; constants that refer to each
// other would visit 2^100 if an evaluation went on after the depth limit.
const stv_test_max_steps = 20000

// Every statement of tests/static_value_cases.json has eslint-utils' value, with two exceptions
// that the test pins too: where the value depends on the environment (`ENV`: the time zone, the
// locale or the clock) veslint answers "not static", and it may do so for a statement written
// under one of the limits of static_value.v (the `tags`). A value that differs from eslint-utils',
// or one where eslint-utils has none, is never accepted; a limit without a statement that veslint
// does not evaluate is not one any more. No evaluation may reach stv_test_max_steps: an
// evaluation that does not end fails here instead of hanging. STV_REPORT=<file> writes every
// difference to that file.
fn test_get_static_value() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'static_value_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	source := (data['source'] or { panic('no source') }).str()
	// The statements: the ones of the declarations, then one per line from `firstCase`.
	mut lines := (data['declarationLines'] or { panic('no declarationLines') }).as_array().map(it.int())
	first_case := (data['firstCase'] or { panic('no firstCase') }).int()
	values := (data['values'] or { panic('no values') }).as_array().map(it.str())
	for i in 0 .. values.len - lines.len {
		lines << first_case + i
	}
	// The limit of each statement, written as runs.
	mut tags := []string{cap: values.len}
	for run in (data['tags'] or { panic('no tags') }).as_array() {
		pair := run.as_array()
		for _ in 0 .. pair[0].int() {
			tags << pair[1].str()
		}
	}
	limits := (data['limits'] or { panic('no limits') }).as_map()
	source_lines := source.split('\n')
	mut c, root := stv_test_checker(source)
	statements := nodes_of_kind(root, c'expression_statement')
	assert statements.len == lines.len
	mut wrong := []string{}
	mut not_evaluated := []string{}
	mut limited := map[string][]string{}
	mut evaluated := map[string]int{}
	mut endless := []string{}
	mut most_steps := 0
	for i, stmt in statements {
		line := position_of(stmt).row + 1
		assert line == lines[i]
		expression := first_named_child(stmt) or { panic('no expression') }
		r, exhausted, steps := c.get_static_value_bounded(expression, stv_test_max_steps)
		got := if r.found { stv_test_serialize(r.value, 0) } else { 'NULL' }
		want := values[i]
		text := source_lines[line - 1]
		if exhausted {
			endless << text
		}
		if steps > most_steps {
			most_steps = steps
		}
		if want == 'ENV' {
			if got != 'NULL' {
				wrong << '${text}\t${want}\t${got}'
			}
		} else if got == want {
			if want != 'NULL' {
				evaluated[tags[i]]++
			}
		} else if got != 'NULL' {
			wrong << '${text}\t${want}\t${got}'
		} else if tags[i] == '' {
			not_evaluated << '${text}\t${want}'
		} else {
			limited[tags[i]] << text
		}
	}
	if report := os.getenv_opt('STV_REPORT') {
		mut out := ['ENDLESS ${endless.len} (most steps: ${most_steps})']
		out << endless
		out << 'WRONG ${wrong.len}'
		out << wrong
		out << 'NOT EVALUATED ${not_evaluated.len}'
		out << not_evaluated
		for name, _ in limits {
			out << 'LIMIT ${name}: ${limited[name].len} not evaluated, ${evaluated[name]} evaluated'
			out << limited[name]
		}
		os.write_file(report, out.join('\n') + '\n') or { panic(err) }
		return
	}
	assert endless == []string{}
	assert wrong == []string{}
	assert not_evaluated == []string{}
	for name, _ in limits {
		assert limited[name].len > 0, 'the limit `${name}` has no statement that is not evaluated'
	}
	for name, _ in limited {
		assert name in limits
	}
	assert statements.len >= 10000
}

// The functions veslint takes for callable are the ones of eslint-utils' callAllowed and
// callPassThrough, which the generator builds from eslint-utils' own source.
fn test_call_allowed_is_eslint_utils() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'static_value_cases.json')) or { panic(err) }
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	mut allowed := (data['callAllowed'] or { panic('no callAllowed') }).as_array().map(it.str())
	mut pass_through := (data['callPassThrough'] or { panic('no callPassThrough') }).as_array().map(it.str())
	mut ours := stv_call_allowed.clone()
	mut ours_pass_through := stv_call_pass_through.clone()
	allowed.sort()
	pass_through.sort()
	ours.sort()
	ours_pass_through.sort()
	assert ours == allowed
	assert ours_pass_through == pass_through
}

// Constants that refer to each other end the evaluation at the depth limit, like the stack
// overflow that eslint-utils catches: before, veslint went on with the other operands, which
// never ended for two constants that name each other twice.
fn test_cyclic_constants_end() {
	source := 'const a = [b, b];\nconst b = a + a;\nconst k = [1];\nk[n]();\nconst n = m + m;\nconst m = n + n;\n(a);\n(b);\n([a, 1]);\n(a || 1);\n(1 || a);\n(k);\n'
	mut c, root := stv_test_checker(source)
	mut got := []string{}
	for stmt in nodes_of_kind(root, c'expression_statement') {
		expression := first_named_child(stmt) or { panic('no expression') }
		r, exhausted, steps := c.get_static_value_bounded(expression, stv_test_max_steps)
		assert !exhausted, c.text(stmt)
		assert steps < 1000, c.text(stmt)
		got << if r.found { stv_test_serialize(r.value, 0) } else { 'NULL' }
	}
	// k[n](), then the six statements in parentheses: only `1 || a` does not evaluate `a`.
	assert got == ['NULL', 'NULL', 'NULL', 'NULL', 'NULL', 'n:1', 'NULL']
}

fn test_static_member_name_and_property_name() {
	mut c, root := stv_test_checker(stv_test_names_source)
	mut want := map[int]string{}
	for entry in stv_test_names_expected {
		line, value := entry.split_once('\t') or { panic(entry) }
		want[line.int()] = value
	}
	mut checked := 0
	for stmt in nodes_of_kind(root, c'expression_statement') {
		member := first_named_child(stmt) or { continue }
		if node_kind(member) !in ['member_expression', 'subscript_expression']
			|| is_estree_chain_root(member) {
			continue
		}
		line := position_of(stmt).row + 1
		expected := want[line] or { continue }
		access_text, name_text := expected.split_once('\t') or { panic(expected) }
		access := c.static_member_name(member)
		name := c.property_name(member)
		// A symbol key gives none: it never equals a name.
		got_access := if a := access {
			'"${a}"'
		} else if access_text == 'symbol' {
			'symbol'
		} else {
			'undefined'
		}
		got_name := if n := name { '"${n}"' } else { 'null' }
		assert got_access == access_text, 'line ${line}'
		assert got_name == name_text, 'line ${line}'
		checked++
	}
	assert checked == stv_test_names_expected.len
	assert c.is_static_member_access_of_value(first_named_child(named_children(root)[5]) or {
		panic('no member')
	}, ['filter', 'reduce'])
}
