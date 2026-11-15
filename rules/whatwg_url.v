module rules

// The basic URL parser and the URL serializer of the URL Standard (https://url.spec.whatwg.org/),
// as `new URL(input, base).href` runs them in Node 26 (ada 4.0.0), for unicorn/relative-url-style:
// special and non-special schemes, credentials, ports, the percent-encode sets, `.` and `..`
// segments, Windows drive letters of file URLs, opaque paths, and IPv4, IPv6, opaque and ASCII
// domain hosts. A domain that needs UTS #46 (a non-ASCII one, or a label that starts with `xn--`)
// is not ported: parsing it fails with `wu_unsupported`. tools/gen_whatwg_url_cases.mjs checks
// this file against Node's URL (tests/whatwg_url_cases.json, the whatwg_url_test.v part of rules/rules_test.v).

// wu_unsupported is the error of a parse that needs a part of the standard that is not ported.
const wu_unsupported = 'unsupported URL'
const wu_failure = 'invalid URL'
// wu_eof stands for the EOF code point.
const wu_eof = rune(0x110000)

// WuUrl is a URL record; a null host, port, query or fragment has its has_* false.
struct WuUrl {
mut:
	scheme       string
	username     string
	password     string
	has_host     bool
	host         string // serialized
	has_port     bool
	port         int
	path         []string
	opaque_path  bool // the path is opaque: path[0] is all of it
	has_query    bool
	query        string
	has_fragment bool
	fragment     string
}

enum WuState {
	scheme_start
	scheme
	no_scheme
	special_relative_or_authority
	path_or_authority
	relative
	relative_slash
	special_authority_slashes
	special_authority_ignore_slashes
	authority
	host
	port
	file
	file_slash
	file_host
	path_start
	path
	opaque_path
	query
	fragment
}

enum WuEncodeSet {
	c0_control
	fragment
	query
	special_query
	path
	userinfo
}

fn wu_is_special(scheme string) bool {
	return scheme in ['ftp', 'file', 'http', 'https', 'ws', 'wss']
}

fn wu_default_port(scheme string) int {
	return match scheme {
		'ftp' { 21 }
		'http', 'ws' { 80 }
		'https', 'wss' { 443 }
		else { -1 }
	}
}

fn wu_is_alpha(c rune) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`)
}

fn wu_is_digit(c rune) bool {
	return c >= `0` && c <= `9`
}

fn wu_is_hex(c rune) bool {
	return wu_is_digit(c) || (c >= `a` && c <= `f`) || (c >= `A` && c <= `F`)
}

fn wu_hex_value(c rune) int {
	return if wu_is_digit(c) {
		int(c - `0`)
	} else if c >= `a` && c <= `f` {
		int(c - `a`) + 10
	} else {
		int(c - `A`) + 10
	}
}

fn wu_lower(c rune) rune {
	return if c >= `A` && c <= `Z` { c + 32 } else { c }
}

// wu_code_points decodes a WTF-8 string into the scalar values of its USVString: a lone
// surrogate (or a byte that is not UTF-8) is U+FFFD, as WebIDL converts JavaScript strings.
fn wu_code_points(s string) []rune {
	mut out := []rune{cap: s.len}
	mut i := 0
	for i < s.len {
		b := s[i]
		mut n := 0
		mut cp := u32(0)
		if b < 0x80 {
			out << rune(b)
			i++
			continue
		} else if b >= 0xc2 && b <= 0xdf {
			n = 2
			cp = u32(b & 0x1f)
		} else if b >= 0xe0 && b <= 0xef {
			n = 3
			cp = u32(b & 0x0f)
		} else if b >= 0xf0 && b <= 0xf4 {
			n = 4
			cp = u32(b & 0x07)
		} else {
			out << rune(0xfffd)
			i++
			continue
		}
		mut ok := i + n <= s.len
		if ok {
			for k in 1 .. n {
				if s[i + k] & 0xc0 != 0x80 {
					ok = false
					break
				}
				cp = (cp << 6) | u32(s[i + k] & 0x3f)
			}
		}
		if !ok || (n == 3 && cp < 0x800) || (n == 4 && (cp < 0x10000 || cp > 0x10ffff)) {
			out << rune(0xfffd)
			i++
			continue
		}
		out << if cp >= 0xd800 && cp <= 0xdfff { rune(0xfffd) } else { rune(cp) }
		i += n
	}
	return out
}

fn wu_string(cps []rune) string {
	return cps.string()
}

// wu_in_encode_set tells whether a code point is in a percent-encode set.
fn wu_in_encode_set(c rune, set WuEncodeSet) bool {
	if c < 0x20 || c > 0x7e {
		return true
	}
	return match set {
		.c0_control { false }
		.fragment { c in [` `, `"`, `<`, `>`, `\``] }
		.query { c in [` `, `"`, `#`, `<`, `>`] }
		.special_query { c in [` `, `"`, `#`, `<`, `>`, `'`] }
		.path { c in [` `, `"`, `#`, `<`, `>`, `?`, `^`, `\``, `{`, `}`] }
		.userinfo {
			c in [` `, `"`, `#`, `<`, `>`, `?`, `^`, `\``, `{`, `}`, `/`, `:`, `;`, `=`, `@`, `[`,
				`\\`, `]`, `|`]
		}
	}
}

// wu_encode is the UTF-8 percent-encoding of a code point with a percent-encode set.
fn wu_encode(c rune, set WuEncodeSet) string {
	if !wu_in_encode_set(c, set) {
		return c.str()
	}
	mut out := ''
	for b in c.str().bytes() {
		out += '%${b:02X}'
	}
	return out
}

// wu_is_drive_letter tells whether a string is a Windows drive letter (`C:` or `C|`), or a
// normalized one (`C:`) with `normalized`.
fn wu_is_drive_letter(s string, normalized bool) bool {
	return s.len == 2 && wu_is_alpha(s[0]) && (s[1] == `:` || (!normalized && s[1] == `|`))
}

// wu_starts_with_drive_letter tells whether the code points from `at` start with a Windows drive
// letter.
fn wu_starts_with_drive_letter(cps []rune, at int) bool {
	if at < 0 || cps.len - at < 2 || !wu_is_alpha(cps[at])
		|| (cps[at + 1] != `:` && cps[at + 1] != `|`) {
		return false
	}
	return cps.len - at == 2 || cps[at + 2] in [`/`, `\\`, `?`, `#`]
}

fn wu_is_single_dot(s string) bool {
	return s == '.' || s.to_lower() == '%2e'
}

fn wu_is_double_dot(s string) bool {
	return s in ['..'] || s.to_lower() in ['.%2e', '%2e.', '%2e%2e']
}

// wu_shorten shortens the path of a URL.
fn wu_shorten(mut url WuUrl) {
	if url.scheme == 'file' && url.path.len == 1 && wu_is_drive_letter(url.path[0], true) {
		return
	}
	if url.path.len > 0 {
		url.path.delete_last()
	}
}

// wu_remaining_starts_with tells whether the code points after `pointer` start with `c`.
fn wu_remaining_starts_with(cps []rune, pointer int, c rune) bool {
	return pointer + 1 < cps.len && cps[pointer + 1] == c
}

// wu_parse is the basic URL parser (without state override) of `input`, against `base` when
// `has_base`.
fn wu_parse(text string, has_base bool, base WuUrl) !WuUrl {
	mut cps := wu_code_points(text)
	// Remove the leading and trailing C0 controls and spaces, then every tab and newline.
	mut start := 0
	mut end := cps.len
	for start < end && cps[start] <= 0x20 {
		start++
	}
	for end > start && cps[end - 1] <= 0x20 {
		end--
	}
	input := cps[start..end].filter(it != `\t` && it != `\n` && it != `\r`)
	mut url := WuUrl{}
	mut state := WuState.scheme_start
	mut buffer := ''
	mut at_sign_seen := false
	mut inside_brackets := false
	mut password_token_seen := false
	mut pointer := 0
	for {
		c := if pointer >= 0 && pointer < input.len { input[pointer] } else { wu_eof }
		special := wu_is_special(url.scheme)
		match state {
			.scheme_start {
				if wu_is_alpha(c) {
					buffer += wu_lower(c).str()
					state = .scheme
				} else {
					state = .no_scheme
					pointer--
				}
			}
			.scheme {
				if wu_is_alpha(c) || wu_is_digit(c) || c in [`+`, `-`, `.`] {
					buffer += wu_lower(c).str()
				} else if c == `:` {
					url.scheme = buffer
					buffer = ''
					if url.scheme == 'file' {
						state = .file
					} else if wu_is_special(url.scheme) && has_base && base.scheme == url.scheme {
						state = .special_relative_or_authority
					} else if wu_is_special(url.scheme) {
						state = .special_authority_slashes
					} else if wu_remaining_starts_with(input, pointer, `/`) {
						state = .path_or_authority
						pointer++
					} else {
						url.opaque_path = true
						url.path = ['']
						state = .opaque_path
					}
				} else {
					buffer = ''
					state = .no_scheme
					pointer = -1
				}
			}
			.no_scheme {
				if !has_base || (base.opaque_path && c != `#`) {
					return error(wu_failure)
				} else if base.opaque_path && c == `#` {
					url.scheme = base.scheme
					url.path = base.path.clone()
					url.opaque_path = true
					url.has_query = base.has_query
					url.query = base.query
					url.has_fragment = true
					url.fragment = ''
					state = .fragment
				} else if base.scheme != 'file' {
					state = .relative
					pointer--
				} else {
					state = .file
					pointer--
				}
			}
			.special_relative_or_authority {
				if c == `/` && wu_remaining_starts_with(input, pointer, `/`) {
					state = .special_authority_ignore_slashes
					pointer++
				} else {
					state = .relative
					pointer--
				}
			}
			.path_or_authority {
				if c == `/` {
					state = .authority
				} else {
					state = .path
					pointer--
				}
			}
			.relative {
				url.scheme = base.scheme
				if c == `/` || (wu_is_special(url.scheme) && c == `\\`) {
					state = .relative_slash
				} else {
					url.username = base.username
					url.password = base.password
					url.has_host = base.has_host
					url.host = base.host
					url.has_port = base.has_port
					url.port = base.port
					url.path = base.path.clone()
					url.has_query = base.has_query
					url.query = base.query
					if c == `?` {
						url.has_query = true
						url.query = ''
						state = .query
					} else if c == `#` {
						url.has_fragment = true
						url.fragment = ''
						state = .fragment
					} else if c != wu_eof {
						url.has_query = false
						url.query = ''
						wu_shorten(mut url)
						state = .path
						pointer--
					}
				}
			}
			.relative_slash {
				if special && (c == `/` || c == `\\`) {
					state = .special_authority_ignore_slashes
				} else if c == `/` {
					state = .authority
				} else {
					url.username = base.username
					url.password = base.password
					url.has_host = base.has_host
					url.host = base.host
					url.has_port = base.has_port
					url.port = base.port
					state = .path
					pointer--
				}
			}
			.special_authority_slashes {
				if c == `/` && wu_remaining_starts_with(input, pointer, `/`) {
					state = .special_authority_ignore_slashes
					pointer++
				} else {
					state = .special_authority_ignore_slashes
					pointer--
				}
			}
			.special_authority_ignore_slashes {
				if c != `/` && c != `\\` {
					state = .authority
					pointer--
				}
			}
			.authority {
				if c == `@` {
					if at_sign_seen {
						buffer = '%40' + buffer
					}
					at_sign_seen = true
					for cp in wu_code_points(buffer) {
						if cp == `:` && !password_token_seen {
							password_token_seen = true
							continue
						}
						encoded := wu_encode(cp, .userinfo)
						if password_token_seen {
							url.password += encoded
						} else {
							url.username += encoded
						}
					}
					buffer = ''
				} else if c in [wu_eof, `/`, `?`, `#`] || (special && c == `\\`) {
					if at_sign_seen && buffer == '' {
						return error(wu_failure)
					}
					pointer -= wu_code_points(buffer).len + 1
					buffer = ''
					state = .host
				} else {
					buffer += c.str()
				}
			}
			.host {
				if c == `:` && !inside_brackets {
					if buffer == '' {
						return error(wu_failure)
					}
					url.host = wu_parse_host(buffer, !special)!
					url.has_host = true
					buffer = ''
					state = .port
				} else if c in [wu_eof, `/`, `?`, `#`] || (special && c == `\\`) {
					pointer--
					if special && buffer == '' {
						return error(wu_failure)
					}
					url.host = wu_parse_host(buffer, !special)!
					url.has_host = true
					buffer = ''
					state = .path_start
				} else {
					if c == `[` {
						inside_brackets = true
					}
					if c == `]` {
						inside_brackets = false
					}
					buffer += c.str()
				}
			}
			.port {
				if wu_is_digit(c) {
					buffer += c.str()
				} else if c in [wu_eof, `/`, `?`, `#`] || (special && c == `\\`) {
					if buffer != '' {
						mut port := 0
						for digit in buffer {
							port = port * 10 + int(digit - `0`)
							if port > 65535 {
								return error(wu_failure)
							}
						}
						url.has_port = port != wu_default_port(url.scheme)
						url.port = port
						buffer = ''
					}
					state = .path_start
					pointer--
				} else {
					return error(wu_failure)
				}
			}
			.file {
				url.scheme = 'file'
				url.has_host = true
				url.host = ''
				if c == `/` || c == `\\` {
					state = .file_slash
				} else if has_base && base.scheme == 'file' {
					url.has_host = base.has_host
					url.host = base.host
					url.path = base.path.clone()
					url.has_query = base.has_query
					url.query = base.query
					if c == `?` {
						url.has_query = true
						url.query = ''
						state = .query
					} else if c == `#` {
						url.has_fragment = true
						url.fragment = ''
						state = .fragment
					} else if c != wu_eof {
						url.has_query = false
						url.query = ''
						if !wu_starts_with_drive_letter(input, pointer) {
							wu_shorten(mut url)
						} else {
							url.path = []
						}
						state = .path
						pointer--
					}
				} else {
					state = .path
					pointer--
				}
			}
			.file_slash {
				if c == `/` || c == `\\` {
					state = .file_host
				} else {
					if has_base && base.scheme == 'file' {
						url.has_host = base.has_host
						url.host = base.host
						if !wu_starts_with_drive_letter(input, pointer) && base.path.len > 0
							&& wu_is_drive_letter(base.path[0], true) {
							url.path << base.path[0]
						}
					}
					state = .path
					pointer--
				}
			}
			.file_host {
				if c in [wu_eof, `/`, `\\`, `?`, `#`] {
					pointer--
					if wu_is_drive_letter(buffer, false) {
						// The buffer is not reset: the path state uses it.
						state = .path
					} else if buffer == '' {
						url.has_host = true
						url.host = ''
						state = .path_start
					} else {
						mut host := wu_parse_host(buffer, false)!
						if host == 'localhost' {
							host = ''
						}
						url.has_host = true
						url.host = host
						buffer = ''
						state = .path_start
					}
				} else {
					buffer += c.str()
				}
			}
			.path_start {
				if special {
					state = .path
					if c != `/` && c != `\\` {
						pointer--
					}
				} else if c == `?` {
					url.has_query = true
					url.query = ''
					state = .query
				} else if c == `#` {
					url.has_fragment = true
					url.fragment = ''
					state = .fragment
				} else if c != wu_eof {
					state = .path
					if c != `/` {
						pointer--
					}
				}
			}
			.path {
				slash := c == `/` || (special && c == `\\`)
				if c == wu_eof || slash || c == `?` || c == `#` {
					if wu_is_double_dot(buffer) {
						wu_shorten(mut url)
						if !slash {
							url.path << ''
						}
					} else if wu_is_single_dot(buffer) && !slash {
						url.path << ''
					} else if !wu_is_single_dot(buffer) {
						if url.scheme == 'file' && url.path.len == 0
							&& wu_is_drive_letter(buffer, false) {
							buffer = buffer[..1] + ':'
						}
						url.path << buffer
					}
					buffer = ''
					if c == `?` {
						url.has_query = true
						url.query = ''
						state = .query
					}
					if c == `#` {
						url.has_fragment = true
						url.fragment = ''
						state = .fragment
					}
				} else {
					buffer += wu_encode(c, .path)
				}
			}
			.opaque_path {
				if c == `?` {
					url.has_query = true
					url.query = ''
					state = .query
				} else if c == `#` {
					url.has_fragment = true
					url.fragment = ''
					state = .fragment
				} else if c == ` ` {
					next := if pointer + 1 < input.len { input[pointer + 1] } else { wu_eof }
					url.path[0] += if next == `?` || next == `#` { '%20' } else { ' ' }
				} else if c != wu_eof {
					url.path[0] += wu_encode(c, .c0_control)
				}
			}
			.query {
				if c == `#` {
					url.has_fragment = true
					url.fragment = ''
					state = .fragment
				} else if c != wu_eof {
					url.query += wu_encode(c, if special { .special_query } else { .query })
				}
			}
			.fragment {
				if c != wu_eof {
					url.fragment += wu_encode(c, .fragment)
				}
			}
		}
		if pointer >= input.len {
			break
		}
		pointer++
	}
	return url
}

// wu_href is the URL serializer.
fn wu_href(url WuUrl) string {
	mut out := url.scheme + ':'
	if url.has_host {
		out += '//'
		if url.username != '' || url.password != '' {
			out += url.username
			if url.password != '' {
				out += ':' + url.password
			}
			out += '@'
		}
		out += url.host
		if url.has_port {
			out += ':${url.port}'
		}
	}
	if url.opaque_path {
		out += url.path[0]
	} else {
		if !url.has_host && url.path.len > 1 && url.path[0] == '' {
			out += '/.'
		}
		for segment in url.path {
			out += '/' + segment
		}
	}
	if url.has_query {
		out += '?' + url.query
	}
	if url.has_fragment {
		out += '#' + url.fragment
	}
	return out
}

// wu_parse_host is the host parser: the serialized host.
fn wu_parse_host(input string, is_opaque bool) !string {
	if input.starts_with('[') {
		if !input.ends_with(']') || input.len < 2 {
			return error(wu_failure)
		}
		return '[' + wu_parse_ipv6(wu_code_points(input[1..input.len - 1]))! + ']'
	}
	if is_opaque {
		return wu_parse_opaque_host(input)
	}
	// The percent-decoding of the input.
	mut bytes := []u8{cap: input.len}
	mut i := 0
	for i < input.len {
		if input[i] == `%` && i + 2 < input.len && wu_is_hex(input[i + 1])
			&& wu_is_hex(input[i + 2]) {
			bytes << u8(wu_hex_value(input[i + 1]) * 16 + wu_hex_value(input[i + 2]))
			i += 3
			continue
		}
		bytes << input[i]
		i++
	}
	domain := bytes.bytestr()
	if bytes.any(it >= 0x80) {
		// UTF-8 that is not valid decodes to U+FFFD, which UTS #46 disallows.
		if wu_string(wu_code_points(domain)) != domain {
			return error(wu_failure)
		}
		return error(wu_unsupported)
	}
	ascii := domain.to_lower()
	if ascii.split('.').any(it.starts_with('xn--')) {
		return error(wu_unsupported)
	}
	if ascii == '' || ascii.bytes().any(wu_is_forbidden_domain_code_point(it)) {
		return error(wu_failure)
	}
	if wu_ends_in_a_number(ascii) {
		return wu_parse_ipv4(ascii)
	}
	return ascii
}

fn wu_is_forbidden_host_code_point(c rune) bool {
	return c in [0, `\t`, `\n`, `\r`, ` `, `#`, `/`, `:`, `<`, `>`, `?`, `@`, `[`, `\\`, `]`, `^`,
		`|`]
}

fn wu_is_forbidden_domain_code_point(b u8) bool {
	return wu_is_forbidden_host_code_point(rune(b)) || b <= 0x1f || b == `%` || b == 0x7f
}

// wu_parse_opaque_host is the opaque-host parser.
fn wu_parse_opaque_host(input string) !string {
	cps := wu_code_points(input)
	if cps.any(wu_is_forbidden_host_code_point(it)) {
		return error(wu_failure)
	}
	mut out := ''
	for c in cps {
		out += wu_encode(c, .c0_control)
	}
	return out
}

// wu_ipv4_number is the IPv4 number parser: none for a failure, and whether the number is not
// decimal. A number that does not fit is saturated (it is too large anyway).
fn wu_ipv4_number(part string) ?u64 {
	if part == '' {
		return none
	}
	mut input := part
	mut radix := u64(10)
	if input.len >= 2 && (input.starts_with('0x') || input.starts_with('0X')) {
		input = input[2..]
		radix = 16
	} else if input.len >= 2 && input[0] == `0` {
		input = input[1..]
		radix = 8
	}
	if input == '' {
		return 0
	}
	mut value := u64(0)
	for c in input {
		digit := if radix == 16 {
			if !wu_is_hex(c) {
				return none
			}
			u64(wu_hex_value(c))
		} else {
			if !wu_is_digit(c) || u64(c - `0`) >= radix {
				return none
			}
			u64(c - `0`)
		}
		value = if value > u64(1) << 40 { value } else { value * radix + digit }
	}
	return value
}

// wu_ends_in_a_number is the ends-in-a-number checker.
fn wu_ends_in_a_number(input string) bool {
	mut parts := input.split('.')
	if parts.last() == '' {
		if parts.len == 1 {
			return false
		}
		parts.delete_last()
	}
	last := parts.last()
	if last != '' && last.bytes().all(wu_is_digit(it)) {
		return true
	}
	wu_ipv4_number(last) or { return false }
	return true
}

// wu_parse_ipv4 is the IPv4 parser: the serialized address.
fn wu_parse_ipv4(input string) !string {
	mut parts := input.split('.')
	if parts.last() == '' && parts.len > 1 {
		parts.delete_last()
	}
	if parts.len > 4 {
		return error(wu_failure)
	}
	mut numbers := []u64{}
	for part in parts {
		numbers << wu_ipv4_number(part) or { return error(wu_failure) }
	}
	for i, n in numbers {
		if i < numbers.len - 1 && n > 255 {
			return error(wu_failure)
		}
	}
	if numbers.last() >= u64(1) << (8 * (5 - numbers.len)) {
		return error(wu_failure)
	}
	mut ipv4 := numbers.last()
	for i in 0 .. numbers.len - 1 {
		ipv4 += numbers[i] << (8 * (3 - i))
	}
	return '${(ipv4 >> 24) & 255}.${(ipv4 >> 16) & 255}.${(ipv4 >> 8) & 255}.${ipv4 & 255}'
}

// wu_parse_ipv6 is the IPv6 parser: the serialized address (without brackets).
fn wu_parse_ipv6(input []rune) !string {
	mut address := []int{len: 8}
	mut piece_index := 0
	mut compress := -1
	mut pointer := 0
	at := fn [input] (i int) rune {
		return if i < input.len { input[i] } else { wu_eof }
	}
	if at(pointer) == `:` {
		if at(pointer + 1) != `:` {
			return error(wu_failure)
		}
		pointer += 2
		piece_index++
		compress = piece_index
	}
	for at(pointer) != wu_eof {
		if piece_index == 8 {
			return error(wu_failure)
		}
		if at(pointer) == `:` {
			if compress != -1 {
				return error(wu_failure)
			}
			pointer++
			piece_index++
			compress = piece_index
			continue
		}
		mut value := 0
		mut length := 0
		for length < 4 && wu_is_hex(at(pointer)) {
			value = value * 16 + wu_hex_value(at(pointer))
			pointer++
			length++
		}
		if at(pointer) == `.` {
			if length == 0 {
				return error(wu_failure)
			}
			pointer -= length
			if piece_index > 6 {
				return error(wu_failure)
			}
			mut numbers_seen := 0
			for at(pointer) != wu_eof {
				mut ipv4_piece := -1
				if numbers_seen > 0 {
					if at(pointer) == `.` && numbers_seen < 4 {
						pointer++
					} else {
						return error(wu_failure)
					}
				}
				if !wu_is_digit(at(pointer)) {
					return error(wu_failure)
				}
				for wu_is_digit(at(pointer)) {
					number := int(at(pointer) - `0`)
					if ipv4_piece == -1 {
						ipv4_piece = number
					} else if ipv4_piece == 0 {
						return error(wu_failure)
					} else {
						ipv4_piece = ipv4_piece * 10 + number
					}
					if ipv4_piece > 255 {
						return error(wu_failure)
					}
					pointer++
				}
				address[piece_index] = address[piece_index] * 0x100 + ipv4_piece
				numbers_seen++
				if numbers_seen == 2 || numbers_seen == 4 {
					piece_index++
				}
			}
			if numbers_seen != 4 {
				return error(wu_failure)
			}
			break
		} else if at(pointer) == `:` {
			pointer++
			if at(pointer) == wu_eof {
				return error(wu_failure)
			}
		} else if at(pointer) != wu_eof {
			return error(wu_failure)
		}
		address[piece_index] = value
		piece_index++
	}
	if compress != -1 {
		mut swaps := piece_index - compress
		piece_index = 7
		for piece_index != 0 && swaps > 0 {
			other := compress + swaps - 1
			address[piece_index], address[other] = address[other], address[piece_index]
			piece_index--
			swaps--
		}
	} else if piece_index != 8 {
		return error(wu_failure)
	}
	return wu_serialize_ipv6(address)
}

// wu_serialize_ipv6 is the IPv6 serializer: the first longest run of two or more zero pieces is
// compressed.
fn wu_serialize_ipv6(address []int) string {
	mut compress := -1
	mut longest := 1
	mut i := 0
	for i < 8 {
		if address[i] != 0 {
			i++
			continue
		}
		mut j := i
		for j < 8 && address[j] == 0 {
			j++
		}
		if j - i > longest {
			longest = j - i
			compress = i
		}
		i = j
	}
	mut out := ''
	mut ignore0 := false
	for index in 0 .. 8 {
		if ignore0 && address[index] == 0 {
			continue
		}
		ignore0 = false
		if compress == index {
			out += if index == 0 { '::' } else { ':' }
			ignore0 = true
			continue
		}
		out += '${address[index]:x}'
		if index != 7 {
			out += ':'
		}
	}
	return out
}

// wu_is_safe_to_add_dot_slash ports isSafeToAddDotSlashToUrl of unicorn/relative-url-style:
// whether `new URL(url, base).href === new URL('./' + url, base).href` (false when one of them
// throws); none when that needs a part of the URL Standard this file does not port.
fn wu_is_safe_to_add_dot_slash(url string, base string) ?bool {
	parsed_base := wu_parse(base, false, WuUrl{}) or {
		return if err.msg() == wu_unsupported { none } else { false }
	}
	mut unsupported := false
	mut hrefs := []string{}
	for input in [url, './' + url] {
		parsed := wu_parse(input, true, parsed_base) or {
			if err.msg() != wu_unsupported {
				return false
			}
			unsupported = true
			continue
		}
		hrefs << wu_href(parsed)
	}
	if unsupported {
		return none
	}
	return hrefs[0] == hrefs[1]
}
