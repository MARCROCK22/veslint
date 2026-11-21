module tsgo

// Types sent once (see api_fastjson.go): with TypeScript in this process, getTypeAtLocations and
// getTypesOfType are asked as veslint/typesAtLocations and veslint/typesOfType, whose answers
// give a type the client was sent before in the same snapshot and project by its id alone. The
// client keeps the types it was sent whole, its symbols already interned, and an answer is the
// array getTypeAtLocations would have given. Most of the types a lint asks for are ones it was
// sent before (on the TypeScript compiler 1.02 million answers, 96,000 different types), and
// reading them took most of the time of an answer.

// SentTypes are the types sent whole in a snapshot and a project, by id.
@[heap]
pub struct SentTypes {
mut:
	types map[int]TypeResponse
}

// sends_types_once tells whether the client asks for types with the methods above: TypeScript in
// this process and VESLINT_TSGO_HELPERS not 0.
fn (c &Client) sends_types_once() bool {
	return c.inproc != 0 && !c.no_helpers
}

fn (mut c Client) sent_types_of(snapshot int, project string) &SentTypes {
	key := '${snapshot} ${project}'
	if sent := c.sent_types[key] {
		return sent
	}
	sent := &SentTypes{}
	c.sent_types[key] = sent
	return sent
}

// forget_sent_types drops the types of a released snapshot.
fn (mut c Client) forget_sent_types(snapshot int) {
	prefix := '${snapshot} '
	for key in c.sent_types.keys() {
		if key.starts_with(prefix) {
			c.sent_types.delete(key)
		}
	}
}

// sent_types_request asks `method` (veslint/typesAtLocations or veslint/typesOfType). With
// VESLINT_CHECK_DECODE set, TypeScript also answers the JSON of getTypeAtLocations or
// getTypesOfType for the same types (the method with `Checked`), which must be what the client
// made of the answer.
fn (mut c Client) sent_types_request(snapshot int, project string, method string, params string) ![]TypeResponse {
	view, buffer := c.inproc_request_view(if check_fast_decode {
		method + 'Checked'
	} else {
		method
	},
		params)!
	defer {
		unsafe { C.free(buffer) }
	}
	mut answer := view
	mut full := ''
	if check_fast_decode {
		line := view.index_u8(`\n`)
		if line < 0 {
			return error('protocol: `${method}Checked` answered without the full types')
		}
		answer = view[..line]
		full = view[line + 1..]
	}
	mut sent := c.sent_types_of(snapshot, project)
	types := if is_null_payload(answer) {
		[]TypeResponse{}
	} else {
		c.read_sent_types(snapshot, answer, mut sent)!
	}
	if check_fast_decode {
		mut want := if is_null_payload(full) {
			[]TypeResponse{}
		} else {
			decode_response[[]TypeResponse](method, full.clone())!
		}
		want = c.intern_types(snapshot, mut want)
		if want != types {
			panic('the types of `${method}` sent once are not the ones sent whole:\n${answer}\n${full}\n${types}\n${want}')
		}
	}
	return types
}

// read_sent_types reads an answer: `null`, an id of a type in `sent`, or a type, which `sent` then
// keeps (in place of the one with its id, sent again because its objectFlags changed).
fn (mut c Client) read_sent_types(snapshot int, payload string, mut sent SentTypes) ![]TypeResponse {
	mut r := FastReader{
		s: payload
	}
	mut out := []TypeResponse{cap: element_count(payload)}
	if r.open_array()! {
		for {
			if r.peek() in [`{`, `n`] {
				// What FastReader does not read is json2's to decode, as in fast_types.
				start := r.i
				t := r.type_response() or {
					r.i = start
					r.skip()!
					decode_response[TypeResponse]('a type', payload[start..r.i])!
				}
				if t.is_null() {
					out << t
				} else {
					interned := c.intern_type(snapshot, t)
					sent.types[t.id] = interned
					out << interned
				}
			} else {
				id := r.int_value()!
				out << sent.types[id] or {
					return error('protocol: tsgo answered the type ${id} by its id before sending it')
				}
			}
			if !r.next(`]`)! {
				break
			}
		}
	}
	r.end()!
	return out
}
