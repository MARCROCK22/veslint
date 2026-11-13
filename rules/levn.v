module rules

import json2
import jsregexp
import math

// ESLint reads the text of a `/* eslint … */` comment first with levn 0.4.1, as an Object
// (`levn.parse("Object", text)` in ConfigCommentParser.parseJSONLikeConfig): a notation looser than
// JSON, where names and texts need no quotes. This ports its three steps (lib/parse-string.js and
// lib/cast.js): the tokens, the lists and objects they make, and the value of each text.
// Three things levn does are not here, each in a text no configuration has:
// - `undefined` is JavaScript's undefined for levn: here an item of a list with it is null, and a
//   property with it is left out;
// - a `#…#` that V8 can read as a date is a Date for levn: here it is that text;
// - a property `"__proto__"` (in quotes) with a list or an object for its value becomes the
//   prototype of the object: here it is left out.

enum LevnKind {
	text
	list
	fields
}

// LevnNode is what levn's parser makes of the tokens: a text (the tokens of a value, joined), a
// list, or the fields of an object in the order of their first appearance.
struct LevnNode {
	kind   LevnKind
	text   string
	items  []LevnNode
	keys   []string
	values []LevnNode
}

struct LevnParser {
	tokens []string
mut:
	pos int
}

const levn_special = [`[`, `]`, `(`, `)`, `}`, `{`, `:`, `,`]

// levn_parse_object ports `levn.parse("Object", text)`: the properties of the object, in the order
// JavaScript lists them, and their values. An error when levn throws.
fn levn_parse_object(text string) !([]string, []json2.Any) {
	mut p := LevnParser{
		tokens: levn_tokens(text)
	}
	// consumeTopLevel: the fields, with or without braces; anything after them makes it a tuple,
	// which is not an Object.
	node := p.fields(p.peek() == '{')!
	if p.pos < p.tokens.len {
		return error('levn: the text is not an object')
	}
	// A rule whose value is undefined stays, with a value that is no severity either.
	object := levn_cast_fields(node, true)!
	mut ids := []string{}
	mut values := []json2.Any{}
	for key in js_object_keys(object) {
		ids << key
		values << object[key] or { json2.Any(json2.null) }
	}
	return ids, values
}

// levn_tokens ports the split of parse-string.js by its tokenRegex: a text in double or single
// quotes, a regular expression literal, a `#…#`, one of `[](){}:,`, or a run of other characters
// (which may have white space inside); the white space between them is dropped.
fn levn_tokens(text string) []string {
	r := text.runes()
	mut tokens := []string{}
	mut i := 0
	for i < r.len {
		if is_js_space(r[i]) {
			i++
			continue
		}
		mut end := -1
		if r[i] in [`"`, `'`, `/`] {
			end = levn_delimited_end(r, i)
			if end >= 0 && r[i] == `/` {
				for end < r.len && ((r[end] >= `a` && r[end] <= `z`) || (r[end] >= `A` && r[end] <= `Z`)) {
					end++
				}
			}
		} else if r[i] == `#` {
			// `#.*#`: up to the last `#` of the line.
			for j := i + 1; j < r.len && r[j] !in [`\n`, `\r`, rune(0x2028), rune(0x2029)]; j++ {
				if r[j] == `#` {
					end = j + 1
				}
			}
		}
		if end < 0 && r[i] in levn_special {
			end = i + 1
		}
		if end < 0 {
			// A character that is neither white space nor special, and then any number of times
			// white space and more such characters.
			end = i + 1
			for {
				mut j := end
				for j < r.len && is_js_space(r[j]) {
					j++
				}
				if j >= r.len || r[j] in levn_special {
					break
				}
				for j < r.len && !is_js_space(r[j]) && r[j] !in levn_special {
					j++
				}
				end = j
			}
		}
		tokens << r[i..end].string()
		i = end
	}
	return tokens
}

// levn_delimited_end is where a token that starts with a quote or a `/` at `start` ends
// (`"(?:\\"|[^"])*"`): after the first such character that has no backslash before it or, when
// there is none, after the last one that has; -1 when there is none at all.
fn levn_delimited_end(r []rune, start int) int {
	mut escaped := -1
	for j := start + 1; j < r.len; j++ {
		if r[j] != r[start] {
			continue
		}
		if r[j - 1] != `\\` || j - 1 == start {
			return j + 1
		}
		escaped = j + 1
	}
	return escaped
}

fn (p &LevnParser) peek() string {
	return if p.pos < p.tokens.len { p.tokens[p.pos] } else { '' }
}

// consume ports consumeOp: the next token must be `op`.
fn (mut p LevnParser) consume(op string) ! {
	if p.peek() != op {
		return error("levn: expected '${op}'")
	}
	p.pos++
}

// value ports consumeValue: the tokens up to one of `until`, joined.
fn (mut p LevnParser) value(until []string) string {
	mut out := ''
	for p.pos < p.tokens.len && p.tokens[p.pos] !in until {
		out += p.tokens[p.pos]
		p.pos++
	}
	return out
}

// element ports consumeElement.
fn (mut p LevnParser) element(until []string) !LevnNode {
	return match p.peek() {
		'[' {
			p.list('[', ']')!
		}
		'(' {
			p.list('(', ')')!
		}
		'{' {
			p.fields(true)!
		}
		else {
			LevnNode{
				text: p.value(until)
			}
		}
	}
}

// list ports consumeList for a list or a tuple in its delimiters.
fn (mut p LevnParser) list(open string, close string) !LevnNode {
	p.consume(open)!
	mut items := []LevnNode{}
	for p.pos < p.tokens.len && p.peek() != close {
		items << p.element([',', close])!
		if p.peek() == ',' {
			p.pos++
		}
	}
	p.consume(close)!
	return LevnNode{
		kind:  .list
		items: items
	}
}

// fields ports consumeFields: `key: value` pairs, with a comma or nothing between them. A key that
// is there again takes the new value in its place.
fn (mut p LevnParser) fields(braces bool) !LevnNode {
	if braces {
		p.consume('{')!
	}
	mut keys := []string{}
	mut values := []LevnNode{}
	for p.pos < p.tokens.len && (!braces || p.peek() != '}') {
		key := p.value([':'])
		p.consume(':')!
		value := p.element(if braces { [',', '}'] } else { [','] })!
		if p.peek() == ',' {
			p.pos++
		}
		at := keys.index(key)
		if at >= 0 {
			values[at] = value
		} else {
			keys << key
			values << value
		}
	}
	if braces {
		p.consume('}')!
	}
	return LevnNode{
		kind:   .fields
		keys:   keys
		values: values
	}
}

// levn_cast_fields ports castFields of cast.js: every property the parser's object has, with its
// name as a String and its value as it comes. That object is made by assignment, so a `__proto__`
// without quotes is not a property: a list or the fields of an object in it are its prototype,
// whose properties are then seen as the object's own.
fn levn_cast_fields(node LevnNode, keep_undefined bool) !map[string]json2.Any {
	mut raw := map[string]json2.Any{}
	mut inherited := LevnNode{}
	mut nodes := map[string]LevnNode{}
	for i, key in node.keys {
		if key == '__proto__' {
			// Only an object becomes the prototype; a text there changes nothing.
			if node.values[i].kind != .text {
				inherited = node.values[i]
			}
			continue
		}
		raw[key] = json2.Any(i)
		nodes[key] = node.values[i]
	}
	mut order := js_object_keys(raw)
	mut from_prototype := map[string]json2.Any{}
	if inherited.kind == .list {
		for i, item in inherited.items {
			if i.str() !in nodes {
				from_prototype[i.str()] = json2.Any(i)
				nodes[i.str()] = item
			}
		}
	} else if inherited.kind == .fields {
		for i, key in inherited.keys {
			if key !in nodes && key != '__proto__' {
				from_prototype[key] = json2.Any(i)
				nodes[key] = inherited.values[i]
			}
		}
	}
	order << js_object_keys(from_prototype)
	mut out := map[string]json2.Any{}
	for key in order {
		value, is_undefined := levn_cast(nodes[key])!
		name := levn_string(key)
		// Assigning to `__proto__` adds no property; and JSON has no undefined.
		if name == '__proto__' || (is_undefined && !keep_undefined) {
			continue
		}
		out[name] = value
	}
	return out
}

// levn_cast ports the cast of a value to the type `*`; the second result tells JavaScript's
// undefined.
fn levn_cast(node LevnNode) !(json2.Any, bool) {
	match node.kind {
		.list {
			mut items := []json2.Any{}
			for item in node.items {
				value, _ := levn_cast(item)!
				items << value
			}
			return json2.Any(items), false
		}
		.fields {
			return json2.Any(levn_cast_fields(node, false)!), false
		}
		.text {
			return levn_cast_text(node.text)
		}
	}
}

// levn_cast_text ports the cast of a text to the first of these it is: undefined, null, NaN, a
// boolean, a number (whatever JavaScript converts to one: the empty text is 0), a regular
// expression literal with flags of `gimy` (levn throws when V8 does not take it), or a String.
fn levn_cast_text(text string) !(json2.Any, bool) {
	match text {
		'undefined' { return json2.Any(json2.null), true }
		'null' { return json2.Any(json2.null), false }
		'NaN' { return json2.Any(math.nan()), false }
		'true' { return json2.Any(true), false }
		'false' { return json2.Any(false), false }
		else {}
	}
	number := js_string_to_number(text)
	if !math.is_nan(number) {
		return json2.Any(number), false
	}
	if text.len >= 2 && text[0] == `/` {
		slash := text.last_index('/') or { 0 }
		flags := text[slash + 1..]
		if slash > 0 && flags.bytes().all(it in [`g`, `i`, `m`, `y`]) {
			jsregexp.regexp_new(utf16_units(text[1..slash]), flags) or {
				return error('levn: invalid regular expression')
			}
			// A RegExp has no properties of its own: for the options of a rule it is an object
			// without any.
			return json2.Any(map[string]json2.Any{}), false
		}
	}
	return json2.Any(levn_string(text)), false
}

// levn_string ports the cast to String: a text in single or double quotes loses them and its
// escapes (a backslash before any character gives that character, except in `\b`, `\f`, `\n`, `\r`,
// `\t` and `\uXXXX`, which are what they are in JSON; a `\u` without its four digits stays as it
// is); any other text is itself.
fn levn_string(text string) string {
	if text.len < 2 || text[0] !in [`'`, `"`] || text[text.len - 1] != text[0] {
		return text
	}
	r := text[1..text.len - 1].runes()
	mut units := []u16{}
	mut i := 0
	for i < r.len {
		if r[i] != `\\` || i + 1 >= r.len {
			units << utf16_units(r[i].str())
			i++
			continue
		}
		next := r[i + 1]
		if next == `u` {
			digits := r[i + 2..if i + 6 <= r.len { i + 6 } else { r.len }].string()
			if digits.len == 4 && digits.bytes().all(it.is_hex_digit()) {
				units << u16(('0x' + digits).int())
				i += 6
			} else {
				units << u16(`\\`)
				i++
			}
			continue
		}
		units << utf16_units(match next {
			`b` { '\b' }
			`f` { '\f' }
			`n` { '\n' }
			`r` { '\r' }
			`t` { '\t' }
			else { next.str() }
		})
		i += 2
	}
	return stv_units_string(units)
}
