module esquery

import math
import math.big
import strconv
import estree
import jsregexp

// The JavaScript values esquery reads from a node with `obj[key]` (getPath and inPath), and the
// operations it applies to them: String() (`"" + value`), typeof, and the relational operators.
// A node has its properties (estree's), and also what ESLint sets or typescript-estree defines on
// it: `type`, `parent`, `range` and `loc` (in UTF-16 units, as in ESLint), and the deprecated
// aliases `assertions`, ImportExpression's `attributes`, TSEnumDeclaration's `members`,
// TSEnumMember's `computed`, TSMappedType's `typeParameter` (a TSTypeParameter of its key and
// constraint) and TSImportType's `argument` (a TSLiteralType of its source). The methods of the prototypes (`params.map`, `name.length`'s
// `toString`…) are functions.

enum JKind {
	undefined
	null
	bool
	number
	string
	bigint
	node     // idx: the node
	list     // idx: index in EsTree.lists
	range    // idx: the node whose `range` it is
	loc      // idx: the node whose `loc` it is
	position // idx: the node, aux: 0 for loc.start, 1 for loc.end
	object   // a plain object (Literal.regex, TemplateElement.value): idx: node, aux: the key
	regexp   // a RegExp (Literal.value): idx: the Literal
	function // s: its name
	proto    // a prototype object reached with `__proto__`
	// mapped_param: the TSTypeParameter TSMappedType's deprecated `typeParameter` gives (idx: the
	// TSMappedType), which is not in the tree.
	mapped_param
	// import_argument: the TSLiteralType TSImportType's deprecated `argument` gives (idx: the
	// TSImportType), which is not in the tree.
	import_argument
}

struct JVal {
	kind JKind
	b    bool
	n    f64
	s    string
	idx  int
	aux  int
}

const undefined_value = JVal{
	kind: .undefined
}

fn node_value(i int) JVal {
	return if i < 0 {
		JVal{
			kind: .null
		}
	} else {
		JVal{
			kind: .node
			idx:  i
		}
	}
}

fn str_value(s string) JVal {
	return JVal{
		kind: .string
		s:    s
	}
}

fn num_value(n f64) JVal {
	return JVal{
		kind: .number
		n:    n
	}
}

fn bool_value(b bool) JVal {
	return JVal{
		kind: .bool
		b:    b
	}
}

fn prop_value(node int, p estree.Prop) JVal {
	return match p.kind {
		.null {
			JVal{
				kind: .null
			}
		}
		.bool {
			bool_value(p.b)
		}
		.number {
			num_value(p.num)
		}
		.string {
			str_value(p.str)
		}
		.node {
			node_value(p.idx)
		}
		.list {
			JVal{
				kind: .list
				idx:  p.idx
			}
		}
		.regex, .template {
			JVal{
				kind: .object
				idx:  node
				aux:  int(p.key)
			}
		}
		.bigint {
			JVal{
				kind: .bigint
				s:    p.str
			}
		}
		.regexp {
			JVal{
				kind: .regexp
				idx:  node
			}
		}
	}
}

// get_prop ports `obj[key]`.
fn get_prop(t &estree.EsTree, obj JVal, key string) JVal {
	match obj.kind {
		.undefined, .null {
			return undefined_value
		}
		.node {
			return node_prop(t, obj.idx, key)
		}
		.list {
			items := t.lists[obj.idx]
			if key == 'length' {
				return num_value(items.len)
			}
			if index := array_index(key) {
				return if index < items.len { node_value(items[index]) } else { undefined_value }
			}
			return proto_member('array', key)
		}
		.range {
			if key == 'length' {
				return num_value(2)
			}
			if index := array_index(key) {
				n := t.nodes[obj.idx]
				return match index {
					0 { num_value(t.utf16_offset(n.start)) }
					1 { num_value(t.utf16_offset(n.end)) }
					else { undefined_value }
				}
			}
			return proto_member('array', key)
		}
		.loc {
			return match key {
				'start' {
					JVal{
						kind: .position
						idx:  obj.idx
						aux:  0
					}
				}
				'end' {
					JVal{
						kind: .position
						idx:  obj.idx
						aux:  1
					}
				}
				else {
					proto_member('object', key)
				}
			}
		}
		.position {
			n := t.nodes[obj.idx]
			line, column := t.line_column(if obj.aux == 0 { n.start } else { n.end })
			return match key {
				'line' { num_value(line) }
				'column' { num_value(column) }
				else { proto_member('object', key) }
			}
		}
		.mapped_param {
			return match key {
				'type' {
					str_value('TSTypeParameter')
				}
				'name' {
					node_value(t.node(obj.idx, .key) or { -1 })
				}
				'constraint' {
					if constraint := t.node(obj.idx, .constraint) {
						node_value(constraint)
					} else {
						undefined_value
					}
				}
				'in', 'out', 'const' {
					bool_value(false)
				}
				else {
					proto_member('object', key)
				}
			}
		}
		.import_argument {
			source := t.node(obj.idx, .source) or { return undefined_value }
			return match key {
				'type' {
					str_value('TSLiteralType')
				}
				'literal' {
					node_value(source)
				}
				'range' {
					JVal{
						kind: .range
						idx:  source
					}
				}
				'loc' {
					JVal{
						kind: .loc
						idx:  source
					}
				}
				else {
					proto_member('object', key)
				}
			}
		}
		.object {
			p := t.prop(obj.idx, unsafe { estree.Key(obj.aux) }) or { return undefined_value }
			if p.kind == .regex {
				return match key {
					'pattern' { str_value(p.str) }
					'flags' { str_value(p.str2) }
					else { proto_member('object', key) }
				}
			}
			return match key {
				'cooked' {
					if p.b {
						JVal{
							kind: .null
						}
					} else {
						str_value(p.str)
					}
				}
				'raw' {
					str_value(p.str2)
				}
				else {
					proto_member('object', key)
				}
			}
		}
		.regexp {
			pattern, flags := regexp_parts(t, obj.idx)
			return match key {
				'source' { str_value(regexp_source(pattern)) }
				'flags' { str_value(canonical_flags(flags)) }
				'global' { bool_value(flags.contains('g')) }
				'ignoreCase' { bool_value(flags.contains('i')) }
				'multiline' { bool_value(flags.contains('m')) }
				'dotAll' { bool_value(flags.contains('s')) }
				'unicode' { bool_value(flags.contains('u')) }
				'unicodeSets' { bool_value(flags.contains('v')) }
				'sticky' { bool_value(flags.contains('y')) }
				'hasIndices' { bool_value(flags.contains('d')) }
				'lastIndex' { num_value(0) }
				else { proto_member('regexp', key) }
			}
		}
		.string {
			if key == 'length' {
				return num_value(utf16_units(obj.s).len)
			}
			if index := array_index(key) {
				units := utf16_units(obj.s)
				return if index < units.len {
					str_value(units_to_string(units[index..index + 1]))
				} else {
					undefined_value
				}
			}
			return proto_member('string', key)
		}
		.number {
			return proto_member('number', key)
		}
		.bool {
			return proto_member('boolean', key)
		}
		.bigint {
			return proto_member('bigint', key)
		}
		.function {
			return match key {
				'name' { str_value(obj.s) }
				else { proto_member('function', key) }
			}
		}
		.proto {
			return proto_member('object', key)
		}
	}
}

// node_prop ports `node[key]` for an ESTree node as ESLint's rules see it.
fn node_prop(t &estree.EsTree, i int, key string) JVal {
	n := t.nodes[i]
	match key {
		'type' {
			return str_value(n.typ.type_name())
		}
		'parent' {
			return node_value(n.parent)
		}
		'range' {
			return JVal{
				kind: .range
				idx:  i
			}
		}
		'loc' {
			return JVal{
				kind: .loc
				idx:  i
			}
		}
		else {}
	}
	if k := estree.key_from_name(key) {
		if p := t.prop(i, k) {
			return prop_value(i, p)
		}
	}
	// Deprecated aliases typescript-estree defines as getters.
	match key {
		'assertions' {
			if n.typ in [.import_declaration, .export_named_declaration, .export_all_declaration] {
				return node_prop(t, i, 'attributes')
			}
		}
		'attributes' {
			if n.typ == .import_expression {
				return node_prop(t, i, 'options')
			}
		}
		'members' {
			if n.typ == .ts_enum_declaration {
				if body := t.node(i, .body) {
					return node_prop(t, body, 'members')
				}
			}
		}
		'typeParameter' {
			if n.typ == .ts_mapped_type {
				return JVal{
					kind: .mapped_param
					idx:  i
				}
			}
		}
		'argument' {
			if n.typ == .ts_import_type {
				return JVal{
					kind: .import_argument
					idx:  i
				}
			}
		}
		'computed' {
			if n.typ == .ts_enum_member {
				// The id of a computed member is its expression: not an Identifier nor a string
				// Literal.
				if id := t.node(i, .id) {
					is_name := t.typ(id) == .identifier
						|| (t.typ(id) == .literal && t.string_of(id, .value) != none)
					return bool_value(!is_name)
				}
			}
		}
		else {}
	}
	return proto_member('object', key)
}

// array_index reads a key that is an array index ("0", "12"; not "01").
fn array_index(key string) ?int {
	if key.len == 0 || key.len > 9 || (key.len > 1 && key[0] == `0`) {
		return none
	}
	for c in key {
		if !c.is_digit() {
			return none
		}
	}
	return key.int()
}

// The methods of the prototypes (Object.getOwnPropertyNames in Node 26), and the name of the
// function each gives.
const prototype_methods = {
	'object':   ['__defineGetter__', '__defineSetter__', '__lookupGetter__', '__lookupSetter__',
		'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable', 'toLocaleString', 'toString',
		'valueOf']
	'array':    ['at', 'concat', 'copyWithin', 'entries', 'every', 'fill', 'filter', 'find', 'findIndex',
		'findLast', 'findLastIndex', 'flat', 'flatMap', 'forEach', 'includes', 'indexOf', 'join',
		'keys', 'lastIndexOf', 'map', 'pop', 'push', 'reduce', 'reduceRight', 'reverse', 'shift',
		'slice', 'some', 'sort', 'splice', 'toLocaleString', 'toReversed', 'toSorted', 'toSpliced',
		'toString', 'unshift', 'values', 'with']
	'string':   ['anchor', 'at', 'big', 'blink', 'bold', 'charAt', 'charCodeAt', 'codePointAt',
		'concat', 'endsWith', 'fixed', 'fontcolor', 'fontsize', 'includes', 'indexOf', 'isWellFormed',
		'italics', 'lastIndexOf', 'link', 'localeCompare', 'match', 'matchAll', 'normalize', 'padEnd',
		'padStart', 'repeat', 'replace', 'replaceAll', 'search', 'slice', 'small', 'split', 'startsWith',
		'strike', 'sub', 'substr', 'substring', 'sup', 'toLocaleLowerCase', 'toLocaleUpperCase',
		'toLowerCase', 'toString', 'toUpperCase', 'toWellFormed', 'trim', 'trimEnd', 'trimLeft',
		'trimRight', 'trimStart', 'valueOf']
	'number':   ['toExponential', 'toFixed', 'toLocaleString', 'toPrecision', 'toString', 'valueOf']
	'boolean':  ['toString', 'valueOf']
	'bigint':   ['toLocaleString', 'toString', 'valueOf']
	'regexp':   ['compile', 'exec', 'test', 'toString']
	'function': ['apply', 'bind', 'call', 'toString']
}

const constructor_names = {
	'object':   'Object'
	'array':    'Array'
	'string':   'String'
	'number':   'Number'
	'boolean':  'Boolean'
	'bigint':   'BigInt'
	'regexp':   'RegExp'
	'function': 'Function'
}

// proto_member is what a key not found on the value itself gives: a method of its prototype (or
// of Object.prototype), the constructor, `__proto__`, or undefined.
fn proto_member(proto string, key string) JVal {
	if key == 'constructor' {
		return JVal{
			kind: .function
			s:    constructor_names[proto] or { 'Object' }
		}
	}
	if key == '__proto__' {
		return JVal{
			kind: .proto
		}
	}
	for name in [proto, 'object'] {
		methods := prototype_methods[name] or { continue }
		if key in methods {
			fname := match key {
				'trimLeft' { 'trimStart' }
				'trimRight' { 'trimEnd' }
				else { key }
			}
			return JVal{
				kind: .function
				s:    fname
			}
		}
	}
	return undefined_value
}

// get_path ports esquery's getPath.
fn get_path(t &estree.EsTree, node int, path []string) JVal {
	mut obj := node_value(node)
	for key in path {
		if obj.kind in [.undefined, .null] {
			return obj
		}
		obj = get_prop(t, obj, key)
	}
	return obj
}

fn regexp_parts(t &estree.EsTree, literal int) (string, string) {
	p := t.prop(literal, .regex) or { return '', '' }
	return p.str, p.str2
}

// regexp_source is the `source` of `new RegExp(pattern)` (V8's EscapeRegExpSource).
fn regexp_source(pattern string) string {
	if pattern == '' {
		return '(?:)'
	}
	return units_to_string(jsregexp.regexp_escape_source(utf16_units(pattern)))
}

// canonical_flags orders flags as RegExp.prototype.flags does.
fn canonical_flags(flags string) string {
	mut out := []u8{}
	for f in 'dgimsuvy' {
		if flags.contains_u8(f) {
			out << f
		}
	}
	return out.bytestr()
}

// js_string ports String(value).
fn js_string(t &estree.EsTree, v JVal) string {
	return match v.kind {
		.undefined {
			'undefined'
		}
		.null {
			'null'
		}
		.bool {
			if v.b { 'true' } else { 'false' }
		}
		.number {
			js_number_to_string(v.n)
		}
		.string {
			v.s
		}
		.bigint {
			v.s
		}
		.list {
			mut parts := []string{}
			for item in t.lists[v.idx] {
				parts << if item < 0 { '' } else { '[object Object]' }
			}
			parts.join(',')
		}
		.range {
			n := t.nodes[v.idx]
			'${t.utf16_offset(n.start)},${t.utf16_offset(n.end)}'
		}
		.regexp {
			pattern, flags := regexp_parts(t, v.idx)
			'/${regexp_source(pattern)}/${canonical_flags(flags)}'
		}
		.function {
			'function ${v.s}() { [native code] }'
		}
		else {
			'[object Object]'
		}
	}
}

// js_typeof ports typeof.
fn js_typeof(v JVal) string {
	return match v.kind {
		.undefined { 'undefined' }
		.bool { 'boolean' }
		.number { 'number' }
		.string { 'string' }
		.bigint { 'bigint' }
		.function { 'function' }
		else { 'object' }
	}
}

// js_number_to_string ports Number::toString(10) (copied from veslint rules/literals.v).
fn js_number_to_string(x f64) string {
	if math.is_nan(x) {
		return 'NaN'
	}
	if x == 0 {
		return '0'
	}
	if x < 0 {
		return '-' + js_number_to_string(-x)
	}
	if math.is_inf(x, 1) {
		return 'Infinity'
	}
	sci := strconv.ftoa_64(x)
	mantissa, exponent := sci.split_once('e') or { return sci }
	digits := mantissa.replace('.', '')
	k := digits.len
	n := exponent.int() + 1
	if k <= n && n <= 21 {
		return digits + '0'.repeat(n - k)
	}
	if 0 < n && n <= 21 {
		return '${digits[..n]}.${digits[n..]}'
	}
	if -6 < n && n <= 0 {
		return '0.${'0'.repeat(-n)}${digits}'
	}
	sign := if n - 1 < 0 { '-' } else { '+' }
	e := math.abs(n - 1)
	if k == 1 {
		return '${digits}e${sign}${e}'
	}
	return '${digits[..1]}.${digits[1..]}e${sign}${e}'
}

// Primitive is a value after ToPrimitive: a number, a string or a bigint (booleans, null and
// undefined are numbers by then).
struct Primitive {
	kind JKind // .number, .string or .bigint
	n    f64
	s    string
}

// to_primitive ports ToPrimitive(value, number), then ToNumeric for what is not a string.
fn to_primitive(t &estree.EsTree, v JVal) Primitive {
	return match v.kind {
		.undefined {
			Primitive{
				kind: .number
				n:    math.nan()
			}
		}
		.null {
			Primitive{
				kind: .number
				n:    0
			}
		}
		.bool {
			Primitive{
				kind: .number
				n:    if v.b { 1 } else { 0 }
			}
		}
		.number {
			Primitive{
				kind: .number
				n:    v.n
			}
		}
		.bigint {
			Primitive{
				kind: .bigint
				s:    v.s
			}
		}
		else {
			// Objects: valueOf gives the object, so toString.
			Primitive{
				kind: .string
				s:    js_string(t, v)
			}
		}
	}
}

// js_less ports IsLessThan(x, y): true, false, or none for undefined (a NaN).
fn js_less(x Primitive, y Primitive) ?bool {
	if x.kind == .string && y.kind == .string {
		return units_less(utf16_units(x.s), utf16_units(y.s))
	}
	if x.kind == .bigint && y.kind == .string {
		ny := string_to_bigint(y.s)?
		return big_less(big.integer_from_string(x.s) or { return none }, ny)
	}
	if x.kind == .string && y.kind == .bigint {
		nx := string_to_bigint(x.s)?
		return big_less(nx, big.integer_from_string(y.s) or { return none })
	}
	nx := if x.kind == .string { string_to_number(x.s) } else { x.n }
	ny := if y.kind == .string { string_to_number(y.s) } else { y.n }
	if x.kind == .bigint && y.kind == .bigint {
		return big_less(big.integer_from_string(x.s) or { return none }, big.integer_from_string(y.s) or {
			return none
		})
	}
	if x.kind == .bigint {
		return bigint_number_compare(x.s, ny, true)
	}
	if y.kind == .bigint {
		return bigint_number_compare(y.s, nx, false)
	}
	if math.is_nan(nx) || math.is_nan(ny) {
		return none
	}
	return nx < ny
}

fn big_less(a big.Integer, b big.Integer) bool {
	return a < b
}

// bigint_number_compare: `bigint < number` (or `number < bigint` when !big_first).
fn bigint_number_compare(digits string, n f64, big_first bool) ?bool {
	if math.is_nan(n) {
		return none
	}
	b := big.integer_from_string(digits) or { return none }
	if math.is_inf(n, 0) {
		return (n > 0) == big_first
	}
	fl := math.floor(n)
	nb := f64_integer_to_big(fl)
	if big_first {
		// b < n: b < n when n is an integer, b <= floor(n) otherwise.
		return if fl == n { b < nb } else { b < nb || b == nb }
	}
	// n < b: n < b when n is an integer, floor(n) < b otherwise.
	return nb < b
}

// f64_integer_to_big converts a finite double without fraction to an integer.
fn f64_integer_to_big(x f64) big.Integer {
	bits := math.f64_bits(x)
	exp := int((bits >> 52) & 0x7ff)
	if exp == 0 {
		return big.integer_from_int(0)
	}
	mant := (bits & ((u64(1) << 52) - 1)) | (u64(1) << 52)
	e := exp - 1075
	mut v := big.integer_from_u64(mant)
	v = if e >= 0 { v.left_shift(u32(e)) } else { v.right_shift(u32(-e)) }
	return if bits >> 63 == 1 { v.neg() } else { v }
}

fn units_less(a []u16, b []u16) bool {
	for i in 0 .. math.min(a.len, b.len) {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	return a.len < b.len
}

fn is_js_space(c u32) bool {
	return c in [u32(9), 10, 11, 12, 13, 32, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
		0xfeff] || (c >= 0x2000 && c <= 0x200a)
}

fn js_trim(s string) string {
	runes := s.runes()
	mut a := 0
	mut b := runes.len
	for a < b && is_js_space(u32(runes[a])) {
		a++
	}
	for b > a && is_js_space(u32(runes[b - 1])) {
		b--
	}
	return runes[a..b].string()
}

// string_to_number ports StringToNumber.
fn string_to_number(s string) f64 {
	t := js_trim(s)
	if t == '' {
		return 0
	}
	if t.len > 2 && t[0] == `0` && (t[1] | 0x20) in [`x`, `o`, `b`] {
		radix := match t[1] | 0x20 {
			`x` { u32(16) }
			`o` { u32(8) }
			else { u32(2) }
		}
		n := big.integer_from_radix(t[2..].to_lower(), radix) or { return math.nan() }
		for c in t[2..] {
			ok := match radix {
				16 { (c >= `0` && c <= `9`) || ((c | 0x20) >= `a` && (c | 0x20) <= `f`) }
				8 { c >= `0` && c <= `7` }
				else { c == `0` || c == `1` }
			}
			if !ok {
				return math.nan()
			}
		}
		return estree.js_parse_float(n.str())
	}
	mut sign := 1.0
	mut body := t
	if body[0] == `+` || body[0] == `-` {
		sign = if body[0] == `-` { -1.0 } else { 1.0 }
		body = body[1..]
	}
	if body == 'Infinity' {
		return sign * math.inf(1)
	}
	// StrUnsignedDecimalLiteral: digits, `.`, digits, exponent.
	mut i := 0
	mut int_digits := 0
	for i < body.len && body[i].is_digit() {
		i++
		int_digits++
	}
	int_part := body[..i]
	mut frac := ''
	if i < body.len && body[i] == `.` {
		i++
		start := i
		for i < body.len && body[i].is_digit() {
			i++
		}
		frac = body[start..i]
	}
	if int_digits == 0 && frac == '' {
		return math.nan()
	}
	mut exp := 0
	if i < body.len && (body[i] == `e` || body[i] == `E`) {
		i++
		mut neg := false
		if i < body.len && (body[i] == `+` || body[i] == `-`) {
			neg = body[i] == `-`
			i++
		}
		start := i
		for i < body.len && body[i].is_digit() {
			if exp < 100000 {
				exp = exp * 10 + int(body[i] - `0`)
			}
			i++
		}
		if i == start {
			return math.nan()
		}
		if neg {
			exp = -exp
		}
	}
	if i != body.len {
		return math.nan()
	}
	return sign * estree.js_decimal(int_part + frac, exp - frac.len)
}

// string_to_bigint ports StringToBigInt; none when the text is no integer.
fn string_to_bigint(s string) ?big.Integer {
	t := js_trim(s)
	if t == '' {
		return big.integer_from_int(0)
	}
	if t.len > 2 && t[0] == `0` && (t[1] | 0x20) in [`x`, `o`, `b`] {
		radix := match t[1] | 0x20 {
			`x` { u32(16) }
			`o` { u32(8) }
			else { u32(2) }
		}
		return big.integer_from_radix(t[2..].to_lower(), radix) or { return none }
	}
	mut body := t
	mut neg := false
	if body[0] == `+` || body[0] == `-` {
		neg = body[0] == `-`
		body = body[1..]
	}
	if body == '' || !body.bytes().all(it.is_digit()) {
		return none
	}
	n := big.integer_from_string(body) or { return none }
	return if neg { n.neg() } else { n }
}
