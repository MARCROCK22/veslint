module tsgo

import json2
import os
import strconv
import strings

// The answers most requests of a lint give (types, symbols and signatures, alone or in lists) are
// read here by hand, without json2: its decoding (a check of the whole text, then a walk of a
// table of its values) was a sixth of a lint of zod with one worker. FastReader reads the JSON
// TypeScript writes for them and fails on anything else (a field of an unexpected kind, a
// number with a fraction where an int goes, an object where a literal value goes…), and then
// json2 decodes the answer, so that the result is always json2's. With VESLINT_CHECK_DECODE set,
// both decode every answer and a difference panics (a test of the client, see tests/run.sh).

const check_fast_decode = os.getenv('VESLINT_CHECK_DECODE') != ''

struct FastReader {
	s string
mut:
	i int
}

fn (mut r FastReader) fail() IError {
	return error('unexpected JSON at ${r.i}')
}

fn (mut r FastReader) skip_space() {
	for r.i < r.s.len {
		c := r.s[r.i]
		if c == ` ` || c == `\n` || c == `\r` || c == `\t` {
			r.i++
		} else {
			break
		}
	}
}

// peek is the next byte that is not a space (0 at the end), which it does not consume.
fn (mut r FastReader) peek() u8 {
	r.skip_space()
	return if r.i < r.s.len { r.s[r.i] } else { 0 }
}

fn (mut r FastReader) expect(c u8) ! {
	if r.peek() != c {
		return r.fail()
	}
	r.i++
}

// end succeeds when nothing but spaces is left.
fn (mut r FastReader) end() ! {
	r.skip_space()
	if r.i != r.s.len {
		return r.fail()
	}
}

// literal consumes `word` (null, true, false) when it is next.
fn (mut r FastReader) literal(word string) bool {
	r.skip_space()
	if r.i + word.len <= r.s.len && unsafe { vmemcmp(r.s.str + r.i, word.str, word.len) } == 0 {
		r.i += word.len
		return true
	}
	return false
}

// open_object consumes `{` and tells whether a key follows (false: the object was `{}`).
fn (mut r FastReader) open_object() !bool {
	r.expect(`{`)!
	if r.peek() == `}` {
		r.i++
		return false
	}
	return true
}

// open_array consumes `[` and tells whether an element follows (false: the array was `[]`).
fn (mut r FastReader) open_array() !bool {
	r.expect(`[`)!
	if r.peek() == `]` {
		r.i++
		return false
	}
	return true
}

// next tells, after a member or an element, whether another follows (`,`) or the container
// ended (`close`).
fn (mut r FastReader) next(close u8) !bool {
	c := r.peek()
	r.i++
	if c == `,` {
		return true
	}
	if c == close {
		return false
	}
	return r.fail()
}

// key reads a member's key and its `:`. It points into the text (no copy): it is only compared.
fn (mut r FastReader) key() !string {
	r.expect(`"`)!
	begin := r.i
	for r.i < r.s.len {
		c := r.s[r.i]
		if c == `"` {
			key := unsafe { tos(r.s.str + begin, r.i - begin) }
			r.i++
			r.expect(`:`)!
			return key
		}
		if c == `\\` || c < 0x20 {
			return r.fail()
		}
		r.i++
	}
	return r.fail()
}

// string reads a string as json2 decodes it: escapes are replaced; a lone surrogate fails.
fn (mut r FastReader) string() !string {
	r.expect(`"`)!
	begin := r.i
	for r.i < r.s.len {
		c := r.s[r.i]
		if c == `"` {
			value := r.s.substr(begin, r.i)
			r.i++
			return value
		}
		if c == `\\` {
			break
		}
		if c < 0x20 {
			return r.fail()
		}
		r.i++
	}
	mut b := strings.new_builder(r.i - begin + 16)
	b.write_string(unsafe { tos(r.s.str + begin, r.i - begin) })
	for r.i < r.s.len {
		c := r.s[r.i]
		if c == `"` {
			r.i++
			return b.str()
		}
		if c < 0x20 {
			return r.fail()
		}
		if c != `\\` {
			b.write_u8(c)
			r.i++
			continue
		}
		if r.i + 1 >= r.s.len {
			return r.fail()
		}
		e := r.s[r.i + 1]
		r.i += 2
		match e {
			`"`, `\\`, `/` {
				b.write_u8(e)
			}
			`b` {
				b.write_u8(`\b`)
			}
			`f` {
				b.write_u8(`\f`)
			}
			`n` {
				b.write_u8(`\n`)
			}
			`r` {
				b.write_u8(`\r`)
			}
			`t` {
				b.write_u8(`\t`)
			}
			`u` {
				point := r.hex4()!
				if point < 0xD800 || point > 0xDFFF {
					b.write_string(rune(point).str())
				} else {
					// A head surrogate and its trail one; anything else goes to json2.
					if point >= 0xDC00 || r.i + 2 > r.s.len || r.s[r.i] != `\\`
						|| r.s[r.i + 1] != `u` {
						return r.fail()
					}
					r.i += 2
					trail := r.hex4()!
					if trail < 0xDC00 || trail > 0xDFFF {
						return r.fail()
					}
					b.write_string(rune(((trail & 0x3FF) | ((point & 0x3FF) << 10)) + 0x10000).str())
				}
			}
			else {
				return r.fail()
			}
		}
	}
	return r.fail()
}

fn (mut r FastReader) hex4() !u32 {
	if r.i + 4 > r.s.len {
		return r.fail()
	}
	mut v := u32(0)
	for _ in 0 .. 4 {
		c := r.s[r.i]
		d := if c >= `0` && c <= `9` {
			u32(c - `0`)
		} else if c >= `a` && c <= `f` {
			u32(c - `a` + 10)
		} else if c >= `A` && c <= `F` {
			u32(c - `A` + 10)
		} else {
			return r.fail()
		}
		v = v * 16 + d
		r.i++
	}
	return v
}

// integer reads a number without fraction or exponent (json2 would read 1e3 as 1000: those go to
// it), of at most 18 digits.
fn (mut r FastReader) integer() !i64 {
	r.skip_space()
	mut negative := false
	if r.i < r.s.len && r.s[r.i] == `-` {
		negative = true
		r.i++
	}
	begin := r.i
	mut v := i64(0)
	for r.i < r.s.len {
		c := r.s[r.i]
		if c < `0` || c > `9` {
			break
		}
		v = v * 10 + i64(c - `0`)
		r.i++
	}
	digits := r.i - begin
	if digits == 0 || digits > 18 {
		return r.fail()
	}
	if r.i < r.s.len && (r.s[r.i] == `.` || r.s[r.i] == `e` || r.s[r.i] == `E`) {
		return r.fail()
	}
	return if negative { -v } else { v }
}

fn (mut r FastReader) int_value() !int {
	return int(r.integer()!)
}

fn (mut r FastReader) u32_value() !u32 {
	v := r.integer()!
	if v < 0 || v > i64(max_u32) {
		return r.fail()
	}
	return u32(v)
}

fn (mut r FastReader) bool_value() !bool {
	if r.literal('true') {
		return true
	}
	if r.literal('false') {
		return false
	}
	return r.fail()
}

fn (mut r FastReader) ints() ![]int {
	mut out := []int{}
	if r.open_array()! {
		for {
			out << r.int_value()!
			if !r.next(`]`)! {
				break
			}
		}
	}
	return out
}

fn (mut r FastReader) strings() ![]string {
	mut out := []string{}
	if r.open_array()! {
		for {
			out << r.string()!
			if !r.next(`]`)! {
				break
			}
		}
	}
	return out
}

// any_value reads a literal type's value as json2 does into a json2.Any: a string, a number (an
// f64, parsed by the same function), a boolean or null.
fn (mut r FastReader) any_value() !json2.Any {
	c := r.peek()
	if c == `"` {
		return json2.Any(r.string()!)
	}
	if c == `-` || (c >= `0` && c <= `9`) {
		begin := r.i
		r.i++
		for r.i < r.s.len {
			d := r.s[r.i]
			if (d >= `0` && d <= `9`) || d == `.` || d == `e` || d == `E` || d == `+` || d == `-` {
				r.i++
			} else {
				break
			}
		}
		return json2.Any(strconv.atof64(r.s.substr(begin, r.i), allow_extra_chars: false) or {
			return r.fail()
		})
	}
	if r.literal('null') {
		return json2.Any(json2.null)
	}
	return json2.Any(r.bool_value()!)
}

// skip passes over a value of any kind (a field the client does not keep).
fn (mut r FastReader) skip() ! {
	c := r.peek()
	match c {
		`"` {
			r.i++
			for r.i < r.s.len {
				d := r.s[r.i]
				if d == `"` {
					r.i++
					return
				}
				r.i += if d == `\\` { 2 } else { 1 }
			}
			return r.fail()
		}
		`{` {
			if r.open_object()! {
				for {
					r.key()!
					r.skip()!
					if !r.next(`}`)! {
						break
					}
				}
			}
		}
		`[` {
			if r.open_array()! {
				for {
					r.skip()!
					if !r.next(`]`)! {
						break
					}
				}
			}
		}
		`t`, `f`, `n` {
			if !r.literal('true') && !r.literal('false') && !r.literal('null') {
				return r.fail()
			}
		}
		else {
			if c == `-` || (c >= `0` && c <= `9`) {
				r.i++
				for r.i < r.s.len {
					d := r.s[r.i]
					if (d >= `0` && d <= `9`) || d == `.` || d == `e` || d == `E` || d == `+`
						|| d == `-` {
						r.i++
					} else {
						break
					}
				}
			} else {
				return r.fail()
			}
		}
	}
}

fn (mut r FastReader) compact_reference() !CompactSymbolReference {
	if r.literal('null') {
		return CompactSymbolReference{}
	}
	mut id := i64(0)
	mut file := ''
	if r.open_object()! {
		for {
			match r.key()! {
				'id' { id = r.integer()! }
				'file' { file = r.string()! }
				else { r.skip()! }
			}
			if !r.next(`}`)! {
				break
			}
		}
	}
	return CompactSymbolReference{
		id:   id
		file: file
	}
}

fn (mut r FastReader) compact_references() ![]CompactSymbolReference {
	mut out := []CompactSymbolReference{}
	if r.open_array()! {
		for {
			out << r.compact_reference()!
			if !r.next(`]`)! {
				break
			}
		}
	}
	return out
}

fn (mut r FastReader) type_response() !TypeResponse {
	// json2 decodes `null` as the zero value, which is the null type of the client.
	if r.literal('null') {
		return TypeResponse{}
	}
	mut id := 0
	mut flags := u32(0)
	mut object_flags := u32(0)
	mut intrinsic_name := ''
	mut target := 0
	mut element_flags := []int{}
	mut is_this_type := false
	mut is_tuple_type := false
	mut alias_type_arguments := []int{}
	mut readonly := false
	mut check_type := 0
	mut extends_type := 0
	mut value := json2.Any([]json2.Any{})
	mut symbol := CompactSymbolReference{}
	mut alias_symbol := CompactSymbolReference{}
	if r.open_object()! {
		for {
			match r.key()! {
				'id' { id = r.int_value()! }
				'flags' { flags = r.u32_value()! }
				'objectFlags' { object_flags = r.u32_value()! }
				'intrinsicName' { intrinsic_name = r.string()! }
				'target' { target = r.int_value()! }
				'elementFlags' { element_flags = r.ints()! }
				'isThisType' { is_this_type = r.bool_value()! }
				'isTupleType' { is_tuple_type = r.bool_value()! }
				'aliasTypeArguments' { alias_type_arguments = r.ints()! }
				'readonly' { readonly = r.bool_value()! }
				'checkType' { check_type = r.int_value()! }
				'extendsType' { extends_type = r.int_value()! }
				'value' { value = r.any_value()! }
				'symbol' { symbol = r.compact_reference()! }
				'aliasSymbol' { alias_symbol = r.compact_reference()! }
				else { r.skip()! }
			}
			if !r.next(`}`)! {
				break
			}
		}
	}
	return TypeResponse{
		id:                     id
		flags:                  flags
		object_flags:           object_flags
		intrinsic_name:         intrinsic_name
		target:                 target
		element_flags:          element_flags
		is_this_type:           is_this_type
		is_tuple_type:          is_tuple_type
		alias_type_arguments:   alias_type_arguments
		readonly:               readonly
		check_type:             check_type
		extends_type:           extends_type
		value:                  value
		symbol_reference:       symbol
		alias_symbol_reference: alias_symbol
	}
}

fn (mut r FastReader) file_descriptor() !SourceFileDescriptor {
	mut file_name := ''
	mut path := ''
	mut content_hash := ''
	mut parse_options_key := ''
	mut script_kind := 0
	mut node_id := ''
	if r.open_object()! {
		for {
			match r.key()! {
				'fileName' { file_name = r.string()! }
				'path' { path = r.string()! }
				'contentHash' { content_hash = r.string()! }
				'parseOptionsKey' { parse_options_key = r.string()! }
				'scriptKind' { script_kind = r.int_value()! }
				'nodeId' { node_id = r.string()! }
				else { r.skip()! }
			}
			if !r.next(`}`)! {
				break
			}
		}
	}
	return SourceFileDescriptor{
		file_name:         file_name
		path:              path
		content_hash:      content_hash
		parse_options_key: parse_options_key
		script_kind:       script_kind
		node_id:           node_id
	}
}

fn (mut r FastReader) symbol_reference() !SymbolReference {
	mut kind := 0
	mut file := SourceFileDescriptor{}
	mut snapshot := 0
	mut project := ''
	mut id := i64(0)
	if r.open_object()! {
		for {
			match r.key()! {
				'kind' { kind = r.int_value()! }
				'file' { file = r.file_descriptor()! }
				'snapshot' { snapshot = r.int_value()! }
				'project' { project = r.string()! }
				'id' { id = r.integer()! }
				else { r.skip()! }
			}
			if !r.next(`}`)! {
				break
			}
		}
	}
	return SymbolReference{
		kind:     kind
		file:     file
		snapshot: snapshot
		project:  project
		id:       id
	}
}

fn (mut r FastReader) symbol_response() !SymbolResponse {
	// json2 decodes `null` as the zero value, which is the null symbol of the client.
	if r.literal('null') {
		return SymbolResponse{}
	}
	mut name := ''
	mut flags := u32(0)
	mut check_flags := u32(0)
	mut declarations := []string{}
	mut value_declaration := ''
	mut reference := SymbolReference{}
	mut parent := CompactSymbolReference{}
	mut export_symbol := CompactSymbolReference{}
	if r.open_object()! {
		for {
			match r.key()! {
				'reference' { reference = r.symbol_reference()! }
				'name' { name = r.string()! }
				'flags' { flags = r.u32_value()! }
				'checkFlags' { check_flags = r.u32_value()! }
				'declarations' { declarations = r.strings()! }
				'valueDeclaration' { value_declaration = r.string()! }
				'parent' { parent = r.compact_reference()! }
				'exportSymbol' { export_symbol = r.compact_reference()! }
				else { r.skip()! }
			}
			if !r.next(`}`)! {
				break
			}
		}
	}
	return SymbolResponse{
		name:                    name
		flags:                   flags
		check_flags:             check_flags
		declarations:            declarations
		value_declaration:       value_declaration
		reference:               reference
		parent_reference:        parent
		export_symbol_reference: export_symbol
	}
}

fn (mut r FastReader) signature_response() !SignatureResponse {
	// json2 decodes `null` as the zero value, which is the null signature of the client.
	if r.literal('null') {
		return SignatureResponse{}
	}
	mut id := 0
	mut flags := u32(0)
	mut parameters := []CompactSymbolReference{}
	mut declaration := ''
	mut type_parameters := []int{}
	mut this_parameter := CompactSymbolReference{}
	if r.open_object()! {
		for {
			match r.key()! {
				'id' { id = r.int_value()! }
				'flags' { flags = r.u32_value()! }
				'parameters' { parameters = r.compact_references()! }
				'declaration' { declaration = r.string()! }
				'typeParameters' { type_parameters = r.ints()! }
				'thisParameter' { this_parameter = r.compact_reference()! }
				else { r.skip()! }
			}
			if !r.next(`}`)! {
				break
			}
		}
	}
	return SignatureResponse{
		id:                       id
		flags:                    flags
		parameters:               parameters
		declaration:              declaration
		type_parameters:          type_parameters
		this_parameter_reference: this_parameter
	}
}

fn fast_type(payload string) !TypeResponse {
	mut r := FastReader{
		s: payload
	}
	t := r.type_response()!
	r.end()!
	return t
}

fn fast_types(payload string) ![]TypeResponse {
	mut r := FastReader{
		s: payload
	}
	// getTypeAtLocations answers thousands of types at once: the room for all of them, instead of
	// copying the array (a few hundred bytes per type) each time it grows.
	mut out := []TypeResponse{cap: element_count(payload)}
	if r.open_array()! {
		for {
			out << r.type_response()!
			if !r.next(`]`)! {
				break
			}
		}
	}
	r.end()!
	return out
}

// element_count counts the elements of a JSON array (0 when the text is not one, or when it is
// empty), as the room to reserve for them: it only follows strings and nesting.
fn element_count(s string) int {
	mut depth := 0
	mut commas := 0
	mut has := false
	mut i := 0
	for i < s.len {
		c := s[i]
		if c == `"` {
			i++
			for i < s.len && s[i] != `"` {
				i += if s[i] == `\\` { 2 } else { 1 }
			}
			has = has || depth == 1
		} else if c == `[` || c == `{` {
			has = has || depth == 1
			depth++
		} else if c == `]` || c == `}` {
			depth--
			if depth <= 0 {
				break
			}
		} else if c == `,` {
			if depth == 1 {
				commas++
			}
		} else if c != ` ` && c != `\t` && c != `\n` && c != `\r` {
			has = has || depth == 1
		}
		i++
	}
	return if has { commas + 1 } else { 0 }
}

fn fast_symbol(payload string) !SymbolResponse {
	mut r := FastReader{
		s: payload
	}
	s := r.symbol_response()!
	r.end()!
	return s
}

fn fast_symbols(payload string) ![]SymbolResponse {
	mut r := FastReader{
		s: payload
	}
	mut out := []SymbolResponse{}
	if r.open_array()! {
		for {
			out << r.symbol_response()!
			if !r.next(`]`)! {
				break
			}
		}
	}
	r.end()!
	return out
}

fn fast_signature(payload string) !SignatureResponse {
	mut r := FastReader{
		s: payload
	}
	s := r.signature_response()!
	r.end()!
	return s
}

fn fast_signatures(payload string) ![]SignatureResponse {
	mut r := FastReader{
		s: payload
	}
	mut out := []SignatureResponse{}
	if r.open_array()! {
		for {
			out << r.signature_response()!
			if !r.next(`]`)! {
				break
			}
		}
	}
	r.end()!
	return out
}

// checked_decode is json2's decoding of `payload`, compared with `fast`'s when VESLINT_CHECK_DECODE
// is set; `fast` is used when it can read the payload.
fn checked_decode[T](method string, payload string, fast fn (string) !T) !T {
	value := fast(payload) or { return decode_response[T](method, payload)! }
	if check_fast_decode {
		want := decode_response[T](method, payload)!
		if want != value {
			panic("the fast decoding of the answer to `${method}` is not json2's:\n${payload}\n${value}\n${want}")
		}
	}
	return value
}
