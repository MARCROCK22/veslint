module tsgo

// Real bytes of `initialize` with a `null` payload, captured from tsgo 7.0.2 (PROMPT.md §3.1);
// 7.1.0-beta frames its messages the same way.
const initialize_hex = '93cc01c40a696e697469616c697a65c4046e756c6c'

fn decode_all(mut d FrameDecoder) []Frame {
	mut frames := []Frame{}
	for {
		f, ok := d.next() or { panic(err) }
		if !ok {
			break
		}
		frames << f
	}
	return frames
}

fn test_initialize_request_bytes() {
	assert encode_frame(msg_request, 'initialize', 'null').hex() == initialize_hex
}

fn test_bin_headers_and_roundtrip() {
	// Header of the payload at index 6: 93 cc type c4 01 'm' <payload>.
	for n in [0, 255, 256, 65535, 65536, 200000] {
		bytes := encode_frame(msg_response, 'm', 'x'.repeat(n))
		expected_tag := if n < 0x100 {
			u8(0xc4)
		} else if n < 0x10000 {
			u8(0xc5)
		} else {
			u8(0xc6)
		}
		assert bytes[6] == expected_tag
		mut d := FrameDecoder{}
		d.push(bytes)
		frames := decode_all(mut d)
		assert frames.len == 1
		assert frames[0].typ == msg_response
		assert frames[0].method == 'm'
		assert frames[0].payload.len == n
		assert d.buf.len == 0
	}
	// Big-endian length: 256 = 01 00 in bin16.
	bytes := encode_frame(msg_response, 'm', 'x'.repeat(256))
	assert bytes[7..9] == [u8(0x01), 0x00]
}

fn test_message_type_as_positive_fixint() {
	mut raw := [u8(0x93), 0x04, 0xc4, 0x01]
	raw << 'm'.bytes()
	raw << [u8(0xc4), 0x02]
	raw << 'ok'.bytes()
	mut d := FrameDecoder{}
	d.push(raw)
	frames := decode_all(mut d)
	assert frames.len == 1
	assert frames[0].typ == 4
	assert frames[0].method == 'm'
	assert frames[0].payload == 'ok'
}

fn test_split_and_concatenated_messages() {
	mut stream := encode_frame(msg_response, 'initialize', '{"a":1}')
	stream << encode_frame(msg_error, 'updateSnapshot', 'boom')
	// Byte by byte: each message appears only when it is complete.
	mut d := FrameDecoder{}
	mut frames := []Frame{}
	for b in stream {
		d.push([b])
		frames << decode_all(mut d)
	}
	assert frames.len == 2
	assert frames[0].method == 'initialize'
	assert frames[0].payload == '{"a":1}'
	assert frames[1].typ == msg_error
	assert frames[1].method == 'updateSnapshot'
	assert frames[1].payload == 'boom'
	// Both messages in a single read.
	mut d2 := FrameDecoder{}
	d2.push(stream)
	both := decode_all(mut d2)
	assert both.map(it.method) == ['initialize', 'updateSnapshot']
}

fn test_bad_marker_is_an_error() {
	mut d := FrameDecoder{}
	d.push([u8(0x92), 0x01, 0x02])
	_, _ := d.next() or {
		assert err.msg().contains('0x93')
		return
	}
	assert false, 'expected a protocol error'
}

fn test_non_bin_method_is_an_error() {
	mut raw := [u8(0x93), 0xcc, 0x04, 0xa1]
	raw << 'm'.bytes()
	mut d := FrameDecoder{}
	d.push(raw)
	_, _ := d.next() or {
		assert err.msg().contains('expected bin')
		return
	}
	assert false, 'expected a protocol error'
}
