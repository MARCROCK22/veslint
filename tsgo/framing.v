module tsgo

// Framing of the `tsc --api` protocol: MessagePack tuples [type, method, payload].

// Message types of the protocol.
const msg_request = u8(1)

// The client's answer to a callback (msg_call).
const msg_call_response = u8(2)

const msg_response = u8(4)

const msg_error = u8(5)

const msg_call = u8(6)

// Frame is a protocol message: a 3-element MessagePack array [type, method, payload], with the
// method and the payload (JSON) encoded as `bin`.
struct Frame {
	typ     u8
	method  string
	payload string
}

// encode_frame serializes a message in the format tsgo expects.
fn encode_frame(typ u8, method string, payload string) []u8 {
	mut out := []u8{cap: 13 + method.len + payload.len}
	out << u8(0x93)
	out << u8(0xcc)
	out << typ
	append_bin(mut out, method.bytes())
	append_bin(mut out, payload.bytes())
	return out
}

fn append_bin(mut out []u8, data []u8) {
	n := data.len
	if n < 0x100 {
		out << u8(0xc4)
		out << u8(n)
	} else if n < 0x10000 {
		out << u8(0xc5)
		out << u8(n >> 8)
		out << u8(n)
	} else {
		out << u8(0xc6)
		out << u8(n >> 24)
		out << u8(n >> 16)
		out << u8(n >> 8)
		out << u8(n)
	}
	out << data
}

// FrameDecoder accumulates the bytes read from tsgo and extracts complete messages, even when
// they arrive split or several in a single read.
struct FrameDecoder {
mut:
	buf []u8
}

fn (mut d FrameDecoder) push(data []u8) {
	d.buf << data
}

// next returns the next complete message; `false` means bytes are still missing.
fn (mut d FrameDecoder) next() !(Frame, bool) {
	if d.buf.len == 0 {
		return Frame{}, false
	}
	if d.buf[0] != 0x93 {
		return error('protocol: expected 0x93 (3-element array) and got 0x${d.buf[0].hex()}')
	}
	if d.buf.len < 2 {
		return Frame{}, false
	}
	mut pos := 1
	mut typ := u8(0)
	tag := d.buf[pos]
	if tag <= 0x7f {
		// positive fixint
		typ = tag
		pos++
	} else if tag == 0xcc {
		if d.buf.len < 3 {
			return Frame{}, false
		}
		typ = d.buf[2]
		pos += 2
	} else {
		return error('protocol: unsupported message type format 0x${tag.hex()}')
	}
	method, after_method, method_ok := read_bin(d.buf, pos)!
	if !method_ok {
		return Frame{}, false
	}
	payload, end, payload_ok := read_bin(d.buf, after_method)!
	if !payload_ok {
		return Frame{}, false
	}
	frame := Frame{
		typ:     typ
		method:  method.bytestr()
		payload: payload.bytestr()
	}
	d.buf = d.buf[end..].clone()
	return frame, true
}

// read_bin reads a MessagePack `bin` at `buf[pos..]` and returns its data, the next position and
// whether it was complete.
fn read_bin(buf []u8, pos int) !([]u8, int, bool) {
	if pos >= buf.len {
		return []u8{}, 0, false
	}
	tag := buf[pos]
	mut header := 0
	mut n := 0
	if tag == 0xc4 {
		header = 2
		if pos + header > buf.len {
			return []u8{}, 0, false
		}
		n = int(buf[pos + 1])
	} else if tag == 0xc5 {
		header = 3
		if pos + header > buf.len {
			return []u8{}, 0, false
		}
		n = (int(buf[pos + 1]) << 8) | int(buf[pos + 2])
	} else if tag == 0xc6 {
		header = 5
		if pos + header > buf.len {
			return []u8{}, 0, false
		}
		n = (int(buf[pos + 1]) << 24) | (int(buf[pos + 2]) << 16) | (int(buf[pos + 3]) << 8) | int(buf[pos + 4])
	} else {
		return error('protocol: expected bin (0xc4/0xc5/0xc6) and got 0x${tag.hex()}')
	}
	data_start := pos + header
	end := data_start + n
	if end > buf.len {
		return []u8{}, 0, false
	}
	return buf[data_start..end].clone(), end, true
}
