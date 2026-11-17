module vue

// A port of vue-eslint-parser's HTML tokenizer (src/html/tokenizer.ts): the WHATWG tokenizer with
// Vue's changes (mustaches, no DOCTYPE, RAWTEXT for <script>). The state functions are ported one
// to one. Positions: `boff` is the byte offset of the current code point; `offset` its UTF-16
// offset, which the gaps and the line terminators are in, as vue-eslint-parser computes with them.

const eof = -1
const null_replacement = 0xfffd

enum State {
	data
	tag_open
	end_tag_open
	tag_name
	rcdata
	rcdata_less_than_sign
	rcdata_end_tag_open
	rcdata_end_tag_name
	rawtext
	rawtext_less_than_sign
	rawtext_end_tag_open
	rawtext_end_tag_name
	before_attribute_name
	attribute_name
	after_attribute_name
	before_attribute_value
	attribute_value_double_quoted
	attribute_value_single_quoted
	attribute_value_unquoted
	after_attribute_value_quoted
	self_closing_start_tag
	bogus_comment
	markup_declaration_open
	comment_start
	comment_start_dash
	comment
	comment_less_than_sign
	comment_less_than_sign_bang
	comment_less_than_sign_bang_dash
	comment_less_than_sign_bang_dash_dash
	comment_end_dash
	comment_end
	comment_end_bang
	cdata_section
	cdata_section_bracket
	cdata_section_end
	character_reference
	named_character_reference
	ambiguous_ampersand
	numeric_character_reference
	hexademical_character_reference_start
	decimal_character_reference_start
	hexademical_character_reference
	decimal_character_reference
	numeric_character_reference_end
	character_reference_end
	v_expression_start
	v_expression_data
	v_expression_end
}

enum TokType as u8 {
	html_association
	html_bogus_comment
	html_cdata_text
	html_comment
	html_end_tag_open
	html_identifier
	html_literal
	html_rcdata_text
	html_raw_text
	html_self_closing_tag_close
	html_tag_close
	html_tag_open
	html_text
	html_whitespace
	v_expression_start
	v_expression_end
}

const tok_type_names = ['HTMLAssociation', 'HTMLBogusComment', 'HTMLCDataText', 'HTMLComment',
	'HTMLEndTagOpen', 'HTMLIdentifier', 'HTMLLiteral', 'HTMLRCDataText', 'HTMLRawText',
	'HTMLSelfClosingTagClose', 'HTMLTagClose', 'HTMLTagOpen', 'HTMLText', 'HTMLWhitespace',
	'VExpressionStart', 'VExpressionEnd']

fn (t TokType) name() string {
	return tok_type_names[int(t)]
}

// HTok is a token of the tokenizer.
struct HTok {
mut:
	typ   TokType
	start int
	end   int
	value string
}

// Options are vue-eslint-parser's `vueFeatures` the parser follows.
pub struct Options {
pub:
	interpolation_as_non_html    bool = true
	filter                       bool = true
	style_css_variable_injection bool = true
}

struct Tokenizer {
	text string
	opts Options
mut:
	gaps             []int // UTF-16
	line_terminators []int // UTF-16
	errors           []ParseError
	last_cp          int
	last_cp_raw      int
	last_bytes       int = 1
	offset           int = -1
	boff             int = -1
	state            State
	return_state     State
	has_vexpr        bool
	vexpr_state      State
	reconsuming      bool
	buffer           []int
	cr_start_offset  int
	cr_code          i64
	// The current token (its value in cur_val), the committed one and the provisional one.
	has_cur       bool
	cur_typ       TokType
	cur_start     int
	cur_val       []u8
	has_committed bool
	committed     HTok
	has_prov      bool
	prov          HTok
	// The value of the last committed HTMLTagOpen token, if any.
	has_last_tag_open bool
	last_tag_open     string
	token_start       int = -1
	// located is the UTF-16 offset the tokenizer's line and column are at.
	located            int = -1
	namespace          Namespace
	expression_enabled bool
	// Where the next `}}` is (see has_close_after).
	close_idx int = -2
}

fn new_tokenizer(text string, opts Options) Tokenizer {
	return Tokenizer{
		text: text
		opts: opts
	}
}

fn (mut t Tokenizer) next_token() ?HTok {
	mut cp := t.last_cp
	for !t.has_committed && (cp != eof || t.reconsuming) {
		if t.has_prov && !t.is_provisional_state() {
			t.commit_provisional_token()
			if t.has_committed {
				break
			}
		}
		if t.reconsuming {
			t.reconsuming = false
			cp = t.last_cp
		} else {
			cp = t.consume_next_code_point()
		}
		t.state = t.step(t.state, cp)
	}
	if t.has_committed {
		t.has_committed = false
		return t.committed
	}
	if t.has_cur {
		t.end_token()
		if t.has_committed {
			t.has_committed = false
			return t.committed
		}
	}
	return none
}

fn (mut t Tokenizer) consume_next_code_point() int {
	if t.boff >= t.text.len {
		t.last_cp = eof
		t.last_cp_raw = eof
		return eof
	}
	t.offset += if t.last_cp >= 0x10000 { 2 } else { 1 }
	t.boff += t.last_bytes
	if t.boff >= t.text.len {
		t.advance_location()
		t.last_cp = eof
		t.last_cp_raw = eof
		t.last_bytes = 1
		return eof
	}
	ucp, n := decode_cp(t.text, t.boff)
	cp := int(ucp)
	t.last_bytes = n
	if is_non_character(cp) {
		t.report_stream_error('noncharacter-in-input-stream')
	}
	if is_control(cp) && !is_whitespace(cp) && cp != 0 {
		t.report_stream_error('control-character-in-input-stream')
	}
	// CRLF -> LF: the LF is skipped.
	if t.last_cp_raw == 0x0d && cp == 0x0a {
		t.last_cp = 0x0a
		t.last_cp_raw = 0x0a
		t.gaps << t.offset
		return t.consume_next_code_point()
	}
	t.advance_location()
	t.last_cp = cp
	t.last_cp_raw = cp
	if cp == 0x0d {
		t.last_cp = 0x0a
		return 0x0a
	}
	return cp
}

fn (mut t Tokenizer) advance_location() {
	if t.last_cp_raw == 0x0a {
		t.line_terminators << t.offset
	}
	t.located = t.offset
}

// report_stream_error reports an error of the input stream, found before the location moved to
// the current code point: its lineNumber and column are the previous code point's.
fn (mut t Tokenizer) report_stream_error(code string) {
	line := sorted_last_index(t.line_terminators, t.located) + 1
	column := t.located - if line == 1 { 0 } else { t.line_terminators[line - 2] }
	t.errors << ParseError{
		message: code
		code:    code
		index:   t.boff
		line:    line
		column:  column
	}
}

@[inline]
fn (mut t Tokenizer) reconsume_as(s State) State {
	t.reconsuming = true
	return s
}

fn (mut t Tokenizer) report_parse_error(code string) {
	t.errors << ParseError{
		message: code
		code:    code
		index:   t.boff
	}
}

@[inline]
fn (mut t Tokenizer) set_start_token_mark() {
	t.token_start = t.boff
}

@[inline]
fn (mut t Tokenizer) clear_start_token_mark() {
	t.token_start = -1
}

fn (mut t Tokenizer) start_token(typ TokType) {
	if t.token_start == -1 {
		t.set_start_token_mark()
	}
	start := t.token_start
	if t.has_cur {
		t.end_token()
	}
	t.token_start = -1
	t.has_cur = true
	t.cur_typ = typ
	t.cur_start = start
	t.cur_val.clear()
}

fn (mut t Tokenizer) end_token() {
	if !t.has_cur {
		panic('vue tokenizer: invalid state')
	}
	if t.token_start == -1 {
		t.set_start_token_mark()
	}
	end := t.token_start
	provisional := t.is_provisional_state()
	t.has_cur = false
	t.token_start = -1
	token := HTok{
		typ:   t.cur_typ
		start: t.cur_start
		end:   end
		value: t.cur_val.bytestr()
	}
	if token.start == end && !provisional {
		return
	}
	if provisional {
		if t.has_prov {
			t.commit_provisional_token()
		}
		t.prov = token
		t.has_prov = true
	} else {
		t.commit_token(token)
	}
}

fn (mut t Tokenizer) commit_token(token HTok) {
	t.committed = token
	t.has_committed = true
	if token.typ == .html_tag_open {
		t.has_last_tag_open = true
		t.last_tag_open = token.value
	}
}

fn (t &Tokenizer) is_provisional_state() bool {
	return t.state in [.rcdata_less_than_sign, .rcdata_end_tag_open, .rcdata_end_tag_name,
		.rawtext_less_than_sign, .rawtext_end_tag_open, .rawtext_end_tag_name]
}

fn (mut t Tokenizer) commit_provisional_token() {
	token := t.prov
	t.has_prov = false
	if token.start < token.end {
		t.commit_token(token)
	}
}

fn (mut t Tokenizer) rollback_provisional_token() {
	t.has_cur = true
	t.cur_typ = t.prov.typ
	t.cur_start = t.prov.start
	t.cur_val.clear()
	t.cur_val << t.prov.value.bytes()
	t.has_prov = false
}

@[inline]
fn (mut t Tokenizer) append(cp int) {
	append_cp(mut t.cur_val, u32(cp))
}

fn (t &Tokenizer) cur_value_is(s string) bool {
	if t.cur_val.len != s.len {
		return false
	}
	for i, c in t.cur_val {
		if s[i] != c {
			return false
		}
	}
	return true
}

fn (t &Tokenizer) is_appropriate_end_tag_open() bool {
	return t.has_cur && t.has_last_tag_open && t.cur_typ == .html_end_tag_open
		&& t.cur_value_is(t.last_tag_open)
}

// has_close_after tells whether a `}}` starts at `from` or later. `from` only grows within a
// file, so the scan is linear overall.
fn (mut t Tokenizer) has_close_after(from int) bool {
	if t.close_idx == -2 || (t.close_idx >= 0 && t.close_idx < from) {
		t.close_idx = t.text.index_after_('}}', from)
	}
	return t.close_idx >= 0
}

fn (mut t Tokenizer) step(s State, cp int) State {
	return match s {
		.data { t.s_data(cp) }
		.tag_open { t.s_tag_open(cp) }
		.end_tag_open { t.s_end_tag_open(cp) }
		.tag_name { t.s_tag_name(cp) }
		.rcdata { t.s_rcdata(cp) }
		.rcdata_less_than_sign { t.s_less_than_sign(cp, .rcdata_end_tag_open, .rcdata) }
		.rcdata_end_tag_open { t.s_end_tag_open_text(cp, .rcdata_end_tag_name, .rcdata) }
		.rcdata_end_tag_name { t.s_rcdata_end_tag_name(cp) }
		.rawtext { t.s_rawtext(cp) }
		.rawtext_less_than_sign { t.s_less_than_sign(cp, .rawtext_end_tag_open, .rawtext) }
		.rawtext_end_tag_open { t.s_end_tag_open_text(cp, .rawtext_end_tag_name, .rawtext) }
		.rawtext_end_tag_name { t.s_rawtext_end_tag_name(cp) }
		.before_attribute_name { t.s_before_attribute_name(cp) }
		.attribute_name { t.s_attribute_name(cp) }
		.after_attribute_name { t.s_after_attribute_name(cp) }
		.before_attribute_value { t.s_before_attribute_value(cp) }
		.attribute_value_double_quoted {
			t.s_attribute_value_quoted(cp, `"`, .attribute_value_double_quoted)
		}
		.attribute_value_single_quoted {
			t.s_attribute_value_quoted(cp, `'`, .attribute_value_single_quoted)
		}
		.attribute_value_unquoted { t.s_attribute_value_unquoted(cp) }
		.after_attribute_value_quoted { t.s_after_attribute_value_quoted(cp) }
		.self_closing_start_tag { t.s_self_closing_start_tag(cp) }
		.bogus_comment { t.s_bogus_comment(cp) }
		.markup_declaration_open { t.s_markup_declaration_open(cp) }
		.comment_start { t.s_comment_start(cp) }
		.comment_start_dash { t.s_comment_start_dash(cp) }
		.comment { t.s_comment(cp) }
		.comment_less_than_sign { t.s_comment_less_than_sign(cp) }
		.comment_less_than_sign_bang { t.s_comment_less_than_sign_bang(cp) }
		.comment_less_than_sign_bang_dash { t.s_comment_less_than_sign_bang_dash(cp) }
		.comment_less_than_sign_bang_dash_dash { t.s_comment_less_than_sign_bang_dash_dash(cp) }
		.comment_end_dash { t.s_comment_end_dash(cp) }
		.comment_end { t.s_comment_end(cp) }
		.comment_end_bang { t.s_comment_end_bang(cp) }
		.cdata_section { t.s_cdata_section(cp) }
		.cdata_section_bracket { t.s_cdata_section_bracket(cp) }
		.cdata_section_end { t.s_cdata_section_end(cp) }
		.character_reference { t.s_character_reference(cp) }
		.named_character_reference { t.s_named_character_reference(cp) }
		.ambiguous_ampersand { t.s_ambiguous_ampersand(cp) }
		.numeric_character_reference { t.s_numeric_character_reference(cp) }
		.hexademical_character_reference_start { t.s_hex_start(cp) }
		.decimal_character_reference_start { t.s_dec_start(cp) }
		.hexademical_character_reference { t.s_hex(cp) }
		.decimal_character_reference { t.s_dec(cp) }
		.numeric_character_reference_end { t.s_numeric_character_reference_end(cp) }
		.character_reference_end { t.s_character_reference_end(cp) }
		.v_expression_start { t.s_v_expression_start(cp) }
		.v_expression_data { t.s_v_expression_data(cp) }
		.v_expression_end { t.s_v_expression_end(cp) }
	}
}

fn (mut t Tokenizer) s_data(cp_ int) State {
	mut cp := cp_
	t.clear_start_token_mark()
	for {
		typ := if is_whitespace(cp) { TokType.html_whitespace } else { TokType.html_text }
		if t.has_cur && t.cur_typ != typ {
			t.end_token()
			return t.reconsume_as(t.state)
		}
		if !t.has_cur {
			t.start_token(typ)
		}
		if cp == `&` {
			t.return_state = .data
			return .character_reference
		}
		if cp == `<` {
			t.set_start_token_mark()
			return .tag_open
		}
		if cp == `{` && t.expression_enabled {
			t.set_start_token_mark()
			t.return_state = .data
			return .v_expression_start
		}
		if cp == `}` && t.expression_enabled {
			t.set_start_token_mark()
			t.return_state = .data
			return .v_expression_end
		}
		if cp == eof {
			return .data
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_rcdata(cp_ int) State {
	mut cp := cp_
	t.clear_start_token_mark()
	for {
		typ := if is_whitespace(cp) { TokType.html_whitespace } else { TokType.html_rcdata_text }
		if t.has_cur && t.cur_typ != typ {
			t.end_token()
			return t.reconsume_as(t.state)
		}
		if !t.has_cur {
			t.start_token(typ)
		}
		if cp == `&` {
			t.return_state = .rcdata
			return .character_reference
		}
		if cp == `<` {
			t.set_start_token_mark()
			return .rcdata_less_than_sign
		}
		if cp == `{` && t.expression_enabled {
			t.set_start_token_mark()
			t.return_state = .rcdata
			return .v_expression_start
		}
		if cp == `}` && t.expression_enabled {
			t.set_start_token_mark()
			t.return_state = .rcdata
			return .v_expression_end
		}
		if cp == eof {
			return .data
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_rawtext(cp_ int) State {
	mut cp := cp_
	t.clear_start_token_mark()
	for {
		typ := if is_whitespace(cp) { TokType.html_whitespace } else { TokType.html_raw_text }
		if t.has_cur && t.cur_typ != typ {
			t.end_token()
			return t.reconsume_as(t.state)
		}
		if !t.has_cur {
			t.start_token(typ)
		}
		if cp == `<` {
			t.set_start_token_mark()
			return .rawtext_less_than_sign
		}
		if cp == `{` && t.expression_enabled {
			t.set_start_token_mark()
			t.return_state = .rawtext
			return .v_expression_start
		}
		if cp == `}` && t.expression_enabled {
			t.set_start_token_mark()
			t.return_state = .rawtext
			return .v_expression_end
		}
		if cp == eof {
			return .data
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_tag_open(cp int) State {
	if cp == `!` {
		return .markup_declaration_open
	}
	if cp == `/` {
		return .end_tag_open
	}
	if is_letter(cp) {
		t.start_token(.html_tag_open)
		return t.reconsume_as(.tag_name)
	}
	if cp == `?` {
		t.report_parse_error('unexpected-question-mark-instead-of-tag-name')
		t.start_token(.html_bogus_comment)
		return t.reconsume_as(.bogus_comment)
	}
	if cp == eof {
		t.clear_start_token_mark()
		t.report_parse_error('eof-before-tag-name')
		t.append(`<`)
		return .data
	}
	t.report_parse_error('invalid-first-character-of-tag-name')
	t.append(`<`)
	return t.reconsume_as(.data)
}

fn (mut t Tokenizer) s_end_tag_open(cp int) State {
	if is_letter(cp) {
		t.start_token(.html_end_tag_open)
		return t.reconsume_as(.tag_name)
	}
	if cp == `>` {
		t.end_token()
		t.report_parse_error('missing-end-tag-name')
		return .data
	}
	if cp == eof {
		t.clear_start_token_mark()
		t.report_parse_error('eof-before-tag-name')
		t.append(`<`)
		t.append(`/`)
		return .data
	}
	t.report_parse_error('invalid-first-character-of-tag-name')
	t.start_token(.html_bogus_comment)
	return t.reconsume_as(.bogus_comment)
}

fn (mut t Tokenizer) s_tag_name(cp_ int) State {
	mut cp := cp_
	for {
		if is_whitespace(cp) {
			t.end_token()
			return .before_attribute_name
		}
		if cp == `/` {
			t.end_token()
			t.set_start_token_mark()
			return .self_closing_start_tag
		}
		if cp == `>` {
			t.start_token(.html_tag_close)
			return .data
		}
		if cp == eof {
			t.report_parse_error('eof-in-tag')
			return .data
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		t.append(if is_upper_letter(cp) { cp + 0x20 } else { cp })
		cp = t.consume_next_code_point()
	}
	return .data
}

// s_less_than_sign is RCDATA_LESS_THAN_SIGN and RAWTEXT_LESS_THAN_SIGN.
fn (mut t Tokenizer) s_less_than_sign(cp int, end_tag_open State, back State) State {
	if cp == `/` {
		t.buffer.clear()
		return end_tag_open
	}
	t.append(`<`)
	return t.reconsume_as(back)
}

// s_end_tag_open_text is RCDATA_END_TAG_OPEN and RAWTEXT_END_TAG_OPEN.
fn (mut t Tokenizer) s_end_tag_open_text(cp int, end_tag_name State, back State) State {
	if is_letter(cp) {
		t.start_token(.html_end_tag_open)
		return t.reconsume_as(end_tag_name)
	}
	t.append(`<`)
	t.append(`/`)
	return t.reconsume_as(back)
}

fn (mut t Tokenizer) s_rcdata_end_tag_name(cp_ int) State {
	mut cp := cp_
	for {
		if is_whitespace(cp) && t.is_appropriate_end_tag_open() {
			t.end_token()
			return .before_attribute_name
		}
		if cp == `/` && t.is_appropriate_end_tag_open() {
			t.end_token()
			t.set_start_token_mark()
			return .self_closing_start_tag
		}
		if cp == `>` && t.is_appropriate_end_tag_open() {
			t.start_token(.html_tag_close)
			return .data
		}
		if !is_letter(cp) {
			t.rollback_provisional_token()
			t.append(`<`)
			t.append(`/`)
			for c in t.buffer {
				t.append(c)
			}
			return t.reconsume_as(.rcdata)
		}
		t.append(if is_upper_letter(cp) { cp + 0x20 } else { cp })
		t.buffer << cp
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_rawtext_end_tag_name(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `/` && t.is_appropriate_end_tag_open() {
			t.end_token()
			t.set_start_token_mark()
			return .self_closing_start_tag
		}
		if cp == `>` && t.is_appropriate_end_tag_open() {
			t.start_token(.html_tag_close)
			return .data
		}
		if is_whitespace(cp) && t.is_appropriate_end_tag_open() {
			t.end_token()
			return .before_attribute_name
		}
		if !is_letter(cp) && !t.maybe_valid_custom_block(cp) {
			t.rollback_provisional_token()
			t.append(`<`)
			t.append(`/`)
			for c in t.buffer {
				t.append(c)
			}
			return t.reconsume_as(.rawtext)
		}
		t.append(if is_upper_letter(cp) { cp + 0x20 } else { cp })
		t.buffer << cp
		cp = t.consume_next_code_point()
	}
	return .data
}

// maybe_valid_custom_block: the last start tag's name starts with the current end tag name and
// that code point, so `</i18n>` can close `<i18n>`.
fn (t &Tokenizer) maybe_valid_custom_block(cp int) bool {
	if !t.has_cur || !t.has_last_tag_open || cp == eof {
		return false
	}
	mut want := t.cur_val.clone()
	append_cp(mut want, u32(cp))
	return t.last_tag_open.starts_with(want.bytestr())
}

fn (mut t Tokenizer) s_before_attribute_name(cp_ int) State {
	mut cp := cp_
	for is_whitespace(cp) {
		cp = t.consume_next_code_point()
	}
	if cp == `/` || cp == `>` || cp == eof {
		return t.reconsume_as(.after_attribute_name)
	}
	if cp == `=` {
		t.report_parse_error('unexpected-equals-sign-before-attribute-name')
		t.start_token(.html_identifier)
		t.append(cp)
		return .attribute_name
	}
	t.start_token(.html_identifier)
	return t.reconsume_as(.attribute_name)
}

fn (mut t Tokenizer) s_attribute_name(cp_ int) State {
	mut cp := cp_
	for {
		if is_whitespace(cp) || cp == `/` || cp == `>` || cp == eof {
			t.end_token()
			return t.reconsume_as(.after_attribute_name)
		}
		if cp == `=` {
			t.start_token(.html_association)
			return .before_attribute_value
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		if cp == `"` || cp == `'` || cp == `<` {
			t.report_parse_error('unexpected-character-in-attribute-name')
		}
		t.append(if is_upper_letter(cp) { cp + 0x20 } else { cp })
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_after_attribute_name(cp_ int) State {
	mut cp := cp_
	for is_whitespace(cp) {
		cp = t.consume_next_code_point()
	}
	if cp == `/` {
		t.set_start_token_mark()
		return .self_closing_start_tag
	}
	if cp == `=` {
		t.start_token(.html_association)
		return .before_attribute_value
	}
	if cp == `>` {
		t.start_token(.html_tag_close)
		return .data
	}
	if cp == eof {
		t.report_parse_error('eof-in-tag')
		return .data
	}
	t.start_token(.html_identifier)
	return t.reconsume_as(.attribute_name)
}

fn (mut t Tokenizer) s_before_attribute_value(cp_ int) State {
	mut cp := cp_
	t.end_token()
	for is_whitespace(cp) {
		cp = t.consume_next_code_point()
	}
	if cp == `>` {
		t.report_parse_error('missing-attribute-value')
		t.start_token(.html_tag_close)
		return .data
	}
	t.start_token(.html_literal)
	if cp == `"` {
		return .attribute_value_double_quoted
	}
	if cp == `'` {
		return .attribute_value_single_quoted
	}
	return t.reconsume_as(.attribute_value_unquoted)
}

fn (mut t Tokenizer) s_attribute_value_quoted(cp_ int, quote int, self State) State {
	mut cp := cp_
	for {
		if cp == quote {
			return .after_attribute_value_quoted
		}
		if cp == `&` {
			t.return_state = self
			return .character_reference
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		if cp == eof {
			t.report_parse_error('eof-in-tag')
			return .data
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_attribute_value_unquoted(cp_ int) State {
	mut cp := cp_
	for {
		if is_whitespace(cp) {
			t.end_token()
			return .before_attribute_name
		}
		if cp == `&` {
			t.return_state = .attribute_value_unquoted
			return .character_reference
		}
		if cp == `>` {
			t.start_token(.html_tag_close)
			return .data
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		if cp == `"` || cp == `'` || cp == `<` || cp == `=` || cp == `\`` {
			t.report_parse_error('unexpected-character-in-unquoted-attribute-value')
		}
		if cp == eof {
			t.report_parse_error('eof-in-tag')
			return .data
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_after_attribute_value_quoted(cp int) State {
	t.end_token()
	if is_whitespace(cp) {
		return .before_attribute_name
	}
	if cp == `/` {
		t.set_start_token_mark()
		return .self_closing_start_tag
	}
	if cp == `>` {
		t.start_token(.html_tag_close)
		return .data
	}
	if cp == eof {
		t.report_parse_error('eof-in-tag')
		return .data
	}
	t.report_parse_error('missing-whitespace-between-attributes')
	return t.reconsume_as(.before_attribute_name)
}

fn (mut t Tokenizer) s_self_closing_start_tag(cp int) State {
	if cp == `>` {
		t.start_token(.html_self_closing_tag_close)
		return .data
	}
	if cp == eof {
		t.report_parse_error('eof-in-tag')
		return .data
	}
	t.report_parse_error('unexpected-solidus-in-tag')
	t.clear_start_token_mark()
	return t.reconsume_as(.before_attribute_name)
}

fn (mut t Tokenizer) s_bogus_comment(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `>` || cp == eof {
			return .data
		}
		if cp == 0 {
			cp = null_replacement
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_markup_declaration_open(cp int) State {
	if cp == `-` && t.boff + 1 < t.text.len && t.text[t.boff + 1] == `-` {
		t.offset++
		t.boff++
		t.located++
		t.start_token(.html_comment)
		return .comment_start
	}
	if cp == `D` && t.text_at(t.boff + 1, 'OCTYPE') {
		t.start_token(.html_bogus_comment)
		t.append(cp)
		return .bogus_comment
	}
	if cp == `[` && t.text_at(t.boff + 1, 'CDATA[') {
		t.offset += 6
		t.boff += 6
		t.located += 6
		if t.namespace == .html {
			t.report_parse_error('cdata-in-html-content')
			t.start_token(.html_bogus_comment)
			t.cur_val << '[CDATA['.bytes()
			return .bogus_comment
		}
		t.start_token(.html_cdata_text)
		return .cdata_section
	}
	t.report_parse_error('incorrectly-opened-comment')
	t.start_token(.html_bogus_comment)
	return t.reconsume_as(.bogus_comment)
}

fn (t &Tokenizer) text_at(at int, s string) bool {
	if at + s.len > t.text.len {
		return false
	}
	for i in 0 .. s.len {
		if t.text[at + i] != s[i] {
			return false
		}
	}
	return true
}

fn (mut t Tokenizer) s_comment_start(cp int) State {
	if cp == `-` {
		return .comment_start_dash
	}
	if cp == `>` {
		t.report_parse_error('abrupt-closing-of-empty-comment')
		return .data
	}
	return t.reconsume_as(.comment)
}

fn (mut t Tokenizer) s_comment_start_dash(cp int) State {
	if cp == `-` {
		return .comment_end
	}
	if cp == `>` {
		t.report_parse_error('abrupt-closing-of-empty-comment')
		return .data
	}
	if cp == eof {
		t.report_parse_error('eof-in-comment')
		return .data
	}
	t.append(`-`)
	return t.reconsume_as(.comment)
}

fn (mut t Tokenizer) s_comment(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `<` {
			t.append(`<`)
			return .comment_less_than_sign
		}
		if cp == `-` {
			return .comment_end_dash
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
			cp = null_replacement
		}
		if cp == eof {
			t.report_parse_error('eof-in-comment')
			return .data
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_comment_less_than_sign(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `!` {
			t.append(cp)
			return .comment_less_than_sign_bang
		}
		if cp != `<` {
			return t.reconsume_as(.comment)
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_comment_less_than_sign_bang(cp int) State {
	if cp == `-` {
		return .comment_less_than_sign_bang_dash
	}
	return t.reconsume_as(.comment)
}

fn (mut t Tokenizer) s_comment_less_than_sign_bang_dash(cp int) State {
	if cp == `-` {
		return .comment_less_than_sign_bang_dash_dash
	}
	return t.reconsume_as(.comment_end_dash)
}

fn (mut t Tokenizer) s_comment_less_than_sign_bang_dash_dash(cp int) State {
	if cp != `>` && cp != eof {
		t.report_parse_error('nested-comment')
	}
	return t.reconsume_as(.comment_end)
}

fn (mut t Tokenizer) s_comment_end_dash(cp int) State {
	if cp == `-` {
		return .comment_end
	}
	if cp == eof {
		t.report_parse_error('eof-in-comment')
		return .data
	}
	t.append(`-`)
	return t.reconsume_as(.comment)
}

fn (mut t Tokenizer) s_comment_end(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `>` {
			return .data
		}
		if cp == `!` {
			return .comment_end_bang
		}
		if cp == eof {
			t.report_parse_error('eof-in-comment')
			return .data
		}
		t.append(`-`)
		if cp != `-` {
			t.append(`-`)
			return t.reconsume_as(.comment)
		}
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_comment_end_bang(cp int) State {
	if cp == `-` {
		t.append(`-`)
		t.append(`!`)
		return .comment_end_dash
	}
	if cp == `>` {
		t.report_parse_error('incorrectly-closed-comment')
		return .data
	}
	if cp == eof {
		t.report_parse_error('eof-in-comment')
		return .data
	}
	t.append(`-`)
	t.append(`!`)
	return t.reconsume_as(.comment)
}

fn (mut t Tokenizer) s_cdata_section(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `]` {
			return .cdata_section_bracket
		}
		if cp == eof {
			t.report_parse_error('eof-in-cdata')
			return .data
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_cdata_section_bracket(cp int) State {
	if cp == `]` {
		return .cdata_section_end
	}
	t.append(`]`)
	return t.reconsume_as(.cdata_section)
}

fn (mut t Tokenizer) s_cdata_section_end(cp_ int) State {
	mut cp := cp_
	for {
		if cp == `>` {
			return .data
		}
		if cp != `]` {
			t.append(`]`)
			t.append(`]`)
			return t.reconsume_as(.cdata_section)
		}
		t.append(`]`)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_character_reference(cp int) State {
	t.cr_start_offset = t.offset - 1
	t.buffer.clear()
	t.buffer << `&`
	if is_digit(cp) || is_letter(cp) {
		return t.reconsume_as(.named_character_reference)
	}
	if cp == `#` {
		t.buffer << cp
		return .numeric_character_reference
	}
	return t.reconsume_as(.character_reference_end)
}

fn (mut t Tokenizer) s_named_character_reference(cp int) State {
	for length in entity_lengths {
		if t.boff + length > t.text.len {
			continue
		}
		name := t.text[t.boff..t.boff + length]
		decoded := entities[name] or { continue }
		semi := name.ends_with(';')
		next := int(name[1])
		t.offset += length - 1
		t.boff += length - 1
		// The column moves with them, without advance_location.
		t.located += length - 1
		if t.return_state in [.attribute_value_double_quoted, .attribute_value_single_quoted,
			.attribute_value_unquoted] && !semi
			&& (next == `=` || is_letter(next) || is_digit(next)) {
			for c in name {
				t.buffer << int(c)
			}
		} else {
			if !semi {
				t.report_parse_error('missing-semicolon-after-character-reference')
			}
			t.buffer.clear()
			mut i := 0
			for i < decoded.len {
				c, n := decode_cp(decoded, i)
				t.buffer << int(c)
				i += n
			}
		}
		return .character_reference_end
	}
	for c in t.buffer {
		t.append(c)
	}
	t.append(cp)
	return .ambiguous_ampersand
}

fn (mut t Tokenizer) s_ambiguous_ampersand(cp_ int) State {
	mut cp := cp_
	for is_digit(cp) || is_letter(cp) {
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	if cp == `;` {
		t.report_parse_error('unknown-named-character-reference')
	}
	return t.reconsume_as(t.return_state)
}

fn (mut t Tokenizer) s_numeric_character_reference(cp int) State {
	t.cr_code = 0
	if cp == `x` || cp == `X` {
		t.buffer << cp
		return .hexademical_character_reference_start
	}
	return t.reconsume_as(.decimal_character_reference_start)
}

fn (mut t Tokenizer) s_hex_start(cp int) State {
	if is_hex_digit(cp) {
		return t.reconsume_as(.hexademical_character_reference)
	}
	t.report_parse_error('absence-of-digits-in-numeric-character-reference')
	return t.reconsume_as(.character_reference_end)
}

fn (mut t Tokenizer) s_dec_start(cp int) State {
	if is_digit(cp) {
		return t.reconsume_as(.decimal_character_reference)
	}
	t.report_parse_error('absence-of-digits-in-numeric-character-reference')
	return t.reconsume_as(.character_reference_end)
}

// The code of a numeric reference grows without bound in JavaScript (a double); it is capped
// here past the range of code points, which keeps the same outcome.
const cr_code_cap = i64(0x7fffffffffff)

fn (mut t Tokenizer) s_hex(cp_ int) State {
	mut cp := cp_
	for {
		if is_digit(cp) {
			t.cr_code = 16 * t.cr_code + (cp - 0x30)
		} else if cp >= `A` && cp <= `F` {
			t.cr_code = 16 * t.cr_code + (cp - 0x37)
		} else if cp >= `a` && cp <= `f` {
			t.cr_code = 16 * t.cr_code + (cp - 0x57)
		} else {
			if cp == `;` {
				return .numeric_character_reference_end
			}
			t.report_parse_error('missing-semicolon-after-character-reference')
			return t.reconsume_as(.numeric_character_reference_end)
		}
		if t.cr_code > cr_code_cap {
			t.cr_code = cr_code_cap
		}
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_dec(cp_ int) State {
	mut cp := cp_
	for {
		if is_digit(cp) {
			t.cr_code = 10 * t.cr_code + (cp - 0x30)
		} else {
			if cp == `;` {
				return .numeric_character_reference_end
			}
			t.report_parse_error('missing-semicolon-after-character-reference')
			return t.reconsume_as(.numeric_character_reference_end)
		}
		if t.cr_code > cr_code_cap {
			t.cr_code = cr_code_cap
		}
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_numeric_character_reference_end(_ int) State {
	mut code := t.cr_code
	if code == 0 {
		t.report_parse_error('null-character-reference')
		code = null_replacement
	} else if code > 0x10ffff {
		t.report_parse_error('character-reference-outside-unicode-range')
		code = null_replacement
	} else if code >= 0xd800 && code <= 0xdfff {
		t.report_parse_error('surrogate-character-reference')
		code = null_replacement
	} else if is_non_character(int(code)) {
		t.report_parse_error('noncharacter-character-reference')
	} else if code == 0x0d || (is_control(int(code)) && !is_whitespace(int(code))) {
		t.report_parse_error('control-character-reference')
		code = i64(alternative_cr[u32(code)] or { u32(code) })
	}
	t.buffer.clear()
	t.buffer << int(code)
	return t.reconsume_as(.character_reference_end)
}

fn (mut t Tokenizer) s_character_reference_end(_ int) State {
	if !t.has_cur {
		panic('vue tokenizer: invalid state')
	}
	mut new_length := 0
	for c in t.buffer {
		t.append(c)
		new_length += if c >= 0x10000 { 2 } else { 1 }
	}
	for i := t.cr_start_offset + new_length; i < t.offset; i++ {
		t.gaps << i
	}
	return t.reconsume_as(t.return_state)
}

fn (mut t Tokenizer) s_v_expression_start(cp int) State {
	if cp == `{` {
		t.start_token(.v_expression_start)
		t.append(`{`)
		t.append(`{`)
		if !t.opts.interpolation_as_non_html {
			return t.return_state
		}
		if !t.has_close_after(t.boff + 1) {
			t.report_parse_error('x-missing-interpolation-end')
			return t.return_state
		}
		t.has_vexpr = true
		t.vexpr_state = t.return_state
		return .v_expression_data
	}
	t.append(`{`)
	return t.reconsume_as(t.return_state)
}

fn (mut t Tokenizer) s_v_expression_data(cp_ int) State {
	mut cp := cp_
	t.clear_start_token_mark()
	state := t.vexpr_state
	for {
		typ := if is_whitespace(cp) {
			TokType.html_whitespace
		} else if state == .rcdata {
			TokType.html_rcdata_text
		} else if state == .rawtext {
			TokType.html_raw_text
		} else {
			TokType.html_text
		}
		if t.has_cur && t.cur_typ != typ {
			t.end_token()
			return t.reconsume_as(t.state)
		}
		if !t.has_cur {
			t.start_token(typ)
		}
		if cp == `&` && state != .rawtext {
			t.return_state = .v_expression_data
			return .character_reference
		}
		if cp == `}` {
			t.set_start_token_mark()
			t.return_state = .v_expression_data
			return .v_expression_end
		}
		if cp == eof {
			t.report_parse_error('x-missing-interpolation-end')
			return .data
		}
		if cp == 0 {
			t.report_parse_error('unexpected-null-character')
		}
		t.append(cp)
		cp = t.consume_next_code_point()
	}
	return .data
}

fn (mut t Tokenizer) s_v_expression_end(cp int) State {
	if cp == `}` {
		t.start_token(.v_expression_end)
		t.append(`}`)
		t.append(`}`)
		if t.has_vexpr {
			s := t.vexpr_state
			t.has_vexpr = false
			return s
		}
		return t.return_state
	}
	t.append(`}`)
	return t.reconsume_as(t.return_state)
}

@[inline]
fn is_whitespace(cp int) bool {
	return cp == 0x09 || cp == 0x0a || cp == 0x0c || cp == 0x0d || cp == 0x20
}

@[inline]
fn is_upper_letter(cp int) bool {
	return cp >= `A` && cp <= `Z`
}

@[inline]
fn is_letter(cp int) bool {
	return (cp >= `a` && cp <= `z`) || (cp >= `A` && cp <= `Z`)
}

@[inline]
fn is_digit(cp int) bool {
	return cp >= `0` && cp <= `9`
}

@[inline]
fn is_hex_digit(cp int) bool {
	return is_digit(cp) || (cp >= `A` && cp <= `F`) || (cp >= `a` && cp <= `f`)
}

@[inline]
fn is_control(cp int) bool {
	return (cp >= 0 && cp <= 0x1f) || (cp >= 0x7f && cp <= 0x9f)
}

@[inline]
fn is_non_character(cp int) bool {
	return (cp >= 0xfdd0 && cp <= 0xfdef) || ((cp & 0xfffe) == 0xfffe && cp <= 0x10ffff)
}
