module regexpp

import math

// RegExpValidator (with its Reader) ported from regexpp 4.12.2. The parser (RegExpParserState) is built in: when
// `build` is set, every validator event also builds the AST (see state.v); when `record` is set, onPatternEnter,
// onPatternLeave and onCharacter are recorded as ValidatorEvent.

pub struct Options {
pub:
	ecma_version int = 2025
	strict       bool
}

// PatternFlags is regexpp's `{ unicode, unicodeSets }` argument of validatePattern/parsePattern. The legacy boolean
// `uFlag` argument is `PatternFlags{ unicode: uFlag }`.
pub struct PatternFlags {
pub:
	unicode      bool
	unicode_sets bool
}

pub enum ValidatorEventKind {
	pattern_enter
	pattern_leave
	character
}

// ValidatorEvent is one call of the validator's onPatternEnter(start), onPatternLeave(start, end) or
// onCharacter(start, end, value) callbacks. `end` and `value` are 0 when the callback has no such argument.
pub struct ValidatorEvent {
pub:
	kind  ValidatorEventKind
	start int
	end   int
	value int
}

struct ClassResult {
	ok                  bool
	may_contain_strings bool
}

struct PropertyResult {
	ok        bool
	key       string
	value     string
	has_value bool
	strings   bool
}

struct ModifierFlagSet {
	ignore_case bool
	multiline   bool
	dot_all     bool
}

struct FlagSet {
mut:
	global       bool
	ignore_case  bool
	multiline    bool
	unicode      bool
	sticky       bool
	dot_all      bool
	has_indices  bool
	unicode_sets bool
}

@[heap]
struct Validator {
	opts Options
mut:
	// Reader
	s          []u16
	i          int
	end        int
	unicode_rd bool
	cp1        int = -1
	w1         int = 1
	cp2        int = -1
	w2         int = 1
	cp3        int = -1
	w3         int = 1
	cp4        int = -1
	// RegExpValidator
	unicode_mode                   bool
	unicode_sets_mode              bool
	n_flag                         bool
	last_int                       f64
	last_min                       f64
	last_max                       f64 = math.inf(1)
	last_str                       string
	last_assertion_is_quantifiable bool
	num_capturing_parens           int
	backreference_names            map[string]bool
	ctx_source                     []u16
	src_kind                       SrcKind
	src_start                      int
	src_end                        int
	gs                             GroupSpecifiers
	// hooks
	record bool
	events []ValidatorEvent
	build  bool
	st     ParserState
}

fn new_validator(opts Options) &Validator {
	return &Validator{
		opts: opts
		gs:   new_group_specifiers(opts.ecma_version >= 2025)
	}
}

// ---- Reader ----

@[inline]
fn (v &Validator) at(i int) int {
	if i >= v.end || i >= v.s.len {
		return -1
	}
	c := int(v.s[i])
	if v.unicode_rd && is_lead_surrogate(c) && i + 1 < v.s.len {
		d := int(v.s[i + 1])
		if is_trail_surrogate(d) {
			return combine_surrogate_pair(c, d)
		}
	}
	return c
}

@[inline]
fn (v &Validator) width(c int) int {
	return if v.unicode_rd && c > 0xffff { 2 } else { 1 }
}

fn (mut v Validator) reader_reset(source []u16, start int, end int, u_flag bool) {
	v.unicode_rd = u_flag
	v.s = source
	v.end = end
	v.rewind(start)
}

fn (mut v Validator) rewind(index int) {
	v.i = index
	v.cp1 = v.at(index)
	v.w1 = v.width(v.cp1)
	v.cp2 = v.at(index + v.w1)
	v.w2 = v.width(v.cp2)
	v.cp3 = v.at(index + v.w1 + v.w2)
	v.w3 = v.width(v.cp3)
	v.cp4 = v.at(index + v.w1 + v.w2 + v.w3)
}

fn (mut v Validator) advance() {
	if v.cp1 != -1 {
		v.i += v.w1
		v.cp1 = v.cp2
		v.w1 = v.w2
		v.cp2 = v.cp3
		v.w2 = v.width(v.cp2)
		v.cp3 = v.cp4
		v.w3 = v.width(v.cp3)
		v.cp4 = v.at(v.i + v.w1 + v.w2 + v.w3)
	}
}

fn (mut v Validator) eat(cp int) bool {
	if v.cp1 == cp {
		v.advance()
		return true
	}
	return false
}

fn (mut v Validator) eat2(cp1 int, cp2 int) bool {
	if v.cp1 == cp1 && v.cp2 == cp2 {
		v.advance()
		v.advance()
		return true
	}
	return false
}

fn (mut v Validator) eat3(cp1 int, cp2 int, cp3 int) bool {
	if v.cp1 == cp1 && v.cp2 == cp2 && v.cp3 == cp3 {
		v.advance()
		v.advance()
		v.advance()
		return true
	}
	return false
}

fn (mut v Validator) reset(source []u16, start int, end int) {
	v.reader_reset(source, start, end, v.unicode_mode)
}

// ---- errors ----

fn (v &Validator) new_error(index int, unicode bool, unicode_sets bool, message string) IError {
	mut source := ''
	if v.src_kind == .literal {
		literal := utf16_to_wtf8(v.s_ctx()[v.src_start..v.src_end])
		if literal != '' {
			source = ': ${literal}'
		}
	} else if v.src_kind == .pattern {
		pattern := utf16_to_wtf8(v.s_ctx()[v.src_start..v.src_end])
		flags_text := (if unicode { 'u' } else { '' }) + (if unicode_sets { 'v' } else { '' })
		source = ': /${pattern}/${flags_text}'
	}
	return SyntaxError{
		message: 'Invalid regular expression${source}: ${message}'
		index:   index
	}
}

fn (v &Validator) s_ctx() []u16 {
	return v.ctx_source
}

fn (v &Validator) raise(message string) IError {
	return v.new_error(v.i, v.unicode_mode && !v.unicode_sets_mode, v.unicode_sets_mode, message)
}

fn (v &Validator) raise_at(message string, index int) IError {
	return v.new_error(index, v.unicode_mode && !v.unicode_sets_mode, v.unicode_sets_mode,
		message)
}

@[inline]
fn (v &Validator) strict() bool {
	return v.opts.strict || v.unicode_mode
}

@[inline]
fn (v &Validator) ecma() int {
	return v.opts.ecma_version
}

// ---- hooks ----

fn (mut v Validator) on_pattern_enter(start int) {
	if v.record {
		v.events << ValidatorEvent{
			kind:  .pattern_enter
			start: start
		}
	}
	if v.build {
		v.st_pattern_enter(start)
	}
}

fn (mut v Validator) on_pattern_leave(start int, end int) ! {
	if v.record {
		v.events << ValidatorEvent{
			kind:  .pattern_leave
			start: start
			end:   end
		}
	}
	if v.build {
		v.st_pattern_leave(end)!
	}
}

fn (mut v Validator) on_character(start int, end int, value int) ! {
	if v.record {
		v.events << ValidatorEvent{
			kind:  .character
			start: start
			end:   end
			value: value
		}
	}
	if v.build {
		v.st_character(start, end, value)!
	}
}

// ---- entry points ----

fn (mut v Validator) validate_literal(source []u16, start int, end int) ! {
	v.ctx_source = source
	v.src_kind = .literal
	v.src_start = start
	v.src_end = end
	v.unicode_sets_mode = false
	v.unicode_mode = false
	v.n_flag = false
	v.reset(source, start, end)
	if v.eat(solidus) && v.eat_regexp_body()! && v.eat(solidus) {
		flag_start := v.i
		mut unicode := false
		mut unicode_sets := false
		for k in flag_start .. source.len {
			if source[k] == latin_small_letter_u {
				unicode = true
			} else if source[k] == latin_small_letter_v {
				unicode_sets = true
			}
		}
		v.validate_flags_internal(source, flag_start, end)!
		v.validate_pattern_internal(source, start + 1, flag_start - 1, PatternFlags{
			unicode:      unicode
			unicode_sets: unicode_sets
		})!
	} else if start >= end {
		return v.raise('Empty')
	} else {
		c := cp_to_wtf8(v.cp1)
		return v.raise("Unexpected character '${c}'")
	}
}

fn (mut v Validator) validate_flags(source []u16, start int, end int) ! {
	v.ctx_source = source
	v.src_kind = .flags
	v.src_start = start
	v.src_end = end
	v.validate_flags_internal(source, start, end)!
}

fn (mut v Validator) validate_pattern(source []u16, start int, end int, flags PatternFlags) ! {
	v.ctx_source = source
	v.src_kind = .pattern
	v.src_start = start
	v.src_end = end
	v.validate_pattern_internal(source, start, end, flags)!
}

fn (mut v Validator) validate_pattern_internal(source []u16, start int, end int, flags PatternFlags) ! {
	// _parseFlagsOptionToMode
	mut unicode := false
	mut unicode_sets := false
	if (flags.unicode || flags.unicode_sets) && v.ecma() >= 2015 {
		unicode = flags.unicode
		if v.ecma() >= 2024 {
			unicode_sets = flags.unicode_sets
		}
	}
	if unicode && unicode_sets {
		return v.new_error(end + 1, unicode, unicode_sets, 'Invalid regular expression flags')
	}
	v.unicode_mode = unicode || unicode_sets
	v.n_flag = (unicode && v.ecma() >= 2018) || unicode_sets || (v.opts.strict && v.ecma() >= 2023)
	v.unicode_sets_mode = unicode_sets
	v.reset(source, start, end)
	v.consume_pattern()!
	if !v.n_flag && v.ecma() >= 2018 && !v.gs.is_empty() {
		v.n_flag = true
		v.rewind(start)
		v.consume_pattern()!
	}
}

fn (mut v Validator) validate_flags_internal(source []u16, start int, end int) ! {
	flags := v.parse_flags(source, start, end)!
	if v.build {
		v.st_flags(start, end, flags)
	}
}

// ---- grammar ----

fn (mut v Validator) eat_regexp_body() !bool {
	start := v.i
	mut in_class := false
	mut escaped := false
	for {
		cp := v.cp1
		if cp == -1 || is_line_terminator(cp) {
			kind := if in_class { 'character class' } else { 'regular expression' }
			return v.raise('Unterminated ${kind}')
		}
		if escaped {
			escaped = false
		} else if cp == reverse_solidus {
			escaped = true
		} else if cp == left_square_bracket {
			in_class = true
		} else if cp == right_square_bracket {
			in_class = false
		} else if (cp == solidus && !in_class) || (cp == asterisk && v.i == start) {
			break
		}
		v.advance()
	}
	return v.i != start
}

fn (mut v Validator) consume_pattern() ! {
	start := v.i
	v.num_capturing_parens = v.count_capturing_parens()
	v.gs.clear()
	v.backreference_names = map[string]bool{}
	v.on_pattern_enter(start)
	v.consume_disjunction()!
	cp := v.cp1
	if v.cp1 != -1 {
		if cp == right_parenthesis {
			return v.raise("Unmatched ')'")
		}
		if cp == reverse_solidus {
			return v.raise('\\ at end of pattern')
		}
		if cp == right_square_bracket || cp == right_curly_bracket {
			return v.raise('Lone quantifier brackets')
		}
		c := cp_to_wtf8(cp)
		return v.raise("Unexpected character '${c}'")
	}
	for name, _ in v.backreference_names {
		if !v.gs.has_in_pattern(name) {
			return v.raise('Invalid named capture referenced')
		}
	}
	v.on_pattern_leave(start, v.i)!
}

fn (mut v Validator) count_capturing_parens() int {
	start := v.i
	mut in_class := false
	mut escaped := false
	mut count := 0
	for v.cp1 != -1 {
		cp := v.cp1
		if escaped {
			escaped = false
		} else if cp == reverse_solidus {
			escaped = true
		} else if cp == left_square_bracket {
			in_class = true
		} else if cp == right_square_bracket {
			in_class = false
		} else if cp == left_parenthesis && !in_class && (v.cp2 != question_mark
			|| (v.cp3 == less_than_sign && v.cp4 != equals_sign && v.cp4 != exclamation_mark)) {
			count += 1
		}
		v.advance()
	}
	v.rewind(start)
	return count
}

fn (mut v Validator) consume_disjunction() ! {
	mut i := 0
	v.gs.enter_disjunction()
	for {
		v.consume_alternative(i)!
		i++
		if !v.eat(vertical_line) {
			break
		}
	}
	if v.consume_quantifier(true)! {
		return v.raise('Nothing to repeat')
	}
	if v.eat(left_curly_bracket) {
		return v.raise('Lone quantifier brackets')
	}
	v.gs.leave_disjunction()
}

fn (mut v Validator) consume_alternative(i int) ! {
	start := v.i
	v.gs.enter_alternative(i)
	if v.build {
		v.st_alternative_enter(start)!
	}
	for v.cp1 != -1 && v.consume_term()! {
	}
	if v.build {
		v.st_alternative_leave(v.i)!
	}
}

fn (mut v Validator) consume_term() !bool {
	if v.unicode_mode || v.strict() {
		if v.consume_assertion()! {
			return true
		}
		return v.consume_atom()! && v.consume_optional_quantifier()!
	}
	if v.consume_assertion()! {
		if !v.last_assertion_is_quantifiable || v.consume_optional_quantifier()! {
			return true
		}
	}
	return v.consume_extended_atom()! && v.consume_optional_quantifier()!
}

fn (mut v Validator) consume_optional_quantifier() !bool {
	v.consume_quantifier(false)!
	return true
}

fn (mut v Validator) consume_assertion() !bool {
	start := v.i
	v.last_assertion_is_quantifiable = false
	if v.eat(circumflex_accent) {
		if v.build {
			v.st_edge_assertion(start, v.i, .start)!
		}
		return true
	}
	if v.eat(dollar_sign) {
		if v.build {
			v.st_edge_assertion(start, v.i, .end)!
		}
		return true
	}
	if v.eat2(reverse_solidus, latin_capital_letter_b) {
		if v.build {
			v.st_word_boundary_assertion(start, v.i, true)!
		}
		return true
	}
	if v.eat2(reverse_solidus, latin_small_letter_b) {
		if v.build {
			v.st_word_boundary_assertion(start, v.i, false)!
		}
		return true
	}
	if v.eat2(left_parenthesis, question_mark) {
		lookbehind := v.ecma() >= 2018 && v.eat(less_than_sign)
		mut negate := false
		mut ok := v.eat(equals_sign)
		if !ok {
			negate = v.eat(exclamation_mark)
			ok = negate
		}
		if ok {
			kind := if lookbehind { AssertionKind.lookbehind } else { AssertionKind.lookahead }
			if v.build {
				v.st_lookaround_enter(start, kind, negate)!
			}
			v.consume_disjunction()!
			if !v.eat(right_parenthesis) {
				return v.raise('Unterminated group')
			}
			v.last_assertion_is_quantifiable = !lookbehind && !v.strict()
			if v.build {
				v.st_leave_container(v.i, .assertion)!
			}
			return true
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) consume_quantifier(no_consume bool) !bool {
	mut min := 0.0
	mut max := 0.0
	if v.eat(asterisk) {
		min = 0
		max = math.inf(1)
	} else if v.eat(plus_sign) {
		min = 1
		max = math.inf(1)
	} else if v.eat(question_mark) {
		min = 0
		max = 1
	} else if v.eat_braced_quantifier(no_consume)! {
		min = v.last_min
		max = v.last_max
	} else {
		return false
	}
	greedy := !v.eat(question_mark)
	if !no_consume {
		if v.build {
			v.st_quantifier(v.i, min, max, greedy)!
		}
	}
	return true
}

fn (mut v Validator) eat_braced_quantifier(no_error bool) !bool {
	start := v.i
	if v.eat(left_curly_bracket) {
		if v.eat_decimal_digits() {
			min := v.last_int
			mut max := min
			if v.eat(comma) {
				max = if v.eat_decimal_digits() { v.last_int } else { math.inf(1) }
			}
			if v.eat(right_curly_bracket) {
				if !no_error && max < min {
					return v.raise('numbers out of order in {} quantifier')
				}
				v.last_min = min
				v.last_max = max
				return true
			}
		}
		if !no_error && (v.unicode_mode || v.strict()) {
			return v.raise('Incomplete quantifier')
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) consume_atom() !bool {
	return v.consume_pattern_character()! || v.consume_dot()!
		|| v.consume_reverse_solidus_atom_escape()! || v.consume_character_class()!.ok
		|| v.consume_capturing_group()! || v.consume_uncapturing_group()!
}

fn (mut v Validator) consume_dot() !bool {
	if v.eat(full_stop) {
		if v.build {
			v.st_any_character_set(v.i - 1, v.i)!
		}
		return true
	}
	return false
}

fn (mut v Validator) consume_reverse_solidus_atom_escape() !bool {
	start := v.i
	if v.eat(reverse_solidus) {
		if v.consume_atom_escape()! {
			return true
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) consume_uncapturing_group() !bool {
	start := v.i
	if v.eat2(left_parenthesis, question_mark) {
		if v.build {
			v.st_group_enter(start)!
		}
		if v.ecma() >= 2025 {
			v.consume_modifiers()!
		}
		if !v.eat(colon) {
			v.rewind(start + 1)
			return v.raise('Invalid group')
		}
		v.consume_disjunction()!
		if !v.eat(right_parenthesis) {
			return v.raise('Unterminated group')
		}
		if v.build {
			v.st_leave_container(v.i, .group)!
		}
		return true
	}
	return false
}

fn (mut v Validator) consume_modifiers() !bool {
	start := v.i
	has_add_modifiers := v.eat_modifiers()
	add_modifiers_end := v.i
	has_hyphen := v.eat(hyphen_minus)
	if !has_add_modifiers && !has_hyphen {
		return false
	}
	if v.build {
		v.st_modifiers_enter(start)!
	}
	add_modifiers := v.parse_modifiers(start, add_modifiers_end)!
	if v.build {
		v.st_modifier_flags(start, add_modifiers_end, add_modifiers, true)!
	}
	if has_hyphen {
		modifiers_start := v.i
		if !v.eat_modifiers() && !has_add_modifiers && v.cp1 == colon {
			return v.raise('Invalid empty flags')
		}
		modifiers := v.parse_modifiers(modifiers_start, v.i)!
		// Object.entries order: ignoreCase, multiline, dotAll
		if modifiers.ignore_case && add_modifiers.ignore_case {
			return v.raise("Duplicated flag 'i'")
		}
		if modifiers.multiline && add_modifiers.multiline {
			return v.raise("Duplicated flag 'm'")
		}
		if modifiers.dot_all && add_modifiers.dot_all {
			return v.raise("Duplicated flag 's'")
		}
		if v.build {
			v.st_modifier_flags(modifiers_start, v.i, modifiers, false)!
		}
	}
	if v.build {
		v.st_leave_container(v.i, .modifiers)!
	}
	return true
}

fn (mut v Validator) consume_capturing_group() !bool {
	start := v.i
	if v.eat(left_parenthesis) {
		mut name := ''
		mut has_name := false
		if v.ecma() >= 2018 {
			if v.consume_group_specifier()! {
				name = v.last_str
				has_name = true
			} else if v.cp1 == question_mark {
				v.rewind(start)
				return false
			}
		} else if v.cp1 == question_mark {
			v.rewind(start)
			return false
		}
		if v.build {
			v.st_capturing_group_enter(start, name, has_name)!
		}
		v.consume_disjunction()!
		if !v.eat(right_parenthesis) {
			return v.raise('Unterminated group')
		}
		if v.build {
			v.st_leave_container(v.i, .capturing_group)!
		}
		return true
	}
	return false
}

fn (mut v Validator) consume_extended_atom() !bool {
	return v.consume_dot()! || v.consume_reverse_solidus_atom_escape()!
		|| v.consume_reverse_solidus_followed_by_c()! || v.consume_character_class()!.ok
		|| v.consume_capturing_group()! || v.consume_uncapturing_group()!
		|| v.consume_invalid_braced_quantifier()! || v.consume_extended_pattern_character()!
}

fn (mut v Validator) consume_reverse_solidus_followed_by_c() !bool {
	start := v.i
	if v.cp1 == reverse_solidus && v.cp2 == latin_small_letter_c {
		v.last_int = v.cp1
		v.advance()
		v.on_character(start, v.i, reverse_solidus)!
		return true
	}
	return false
}

fn (mut v Validator) consume_invalid_braced_quantifier() !bool {
	if v.eat_braced_quantifier(true)! {
		return v.raise('Nothing to repeat')
	}
	return false
}

fn (mut v Validator) consume_pattern_character() !bool {
	start := v.i
	cp := v.cp1
	if cp != -1 && !is_syntax_character(cp) {
		v.advance()
		v.on_character(start, v.i, cp)!
		return true
	}
	return false
}

fn (mut v Validator) consume_extended_pattern_character() !bool {
	start := v.i
	cp := v.cp1
	if cp != -1 && cp != circumflex_accent && cp != dollar_sign && cp != reverse_solidus
		&& cp != full_stop && cp != asterisk && cp != plus_sign && cp != question_mark
		&& cp != left_parenthesis && cp != right_parenthesis && cp != left_square_bracket
		&& cp != vertical_line {
		v.advance()
		v.on_character(start, v.i, cp)!
		return true
	}
	return false
}

fn (mut v Validator) consume_group_specifier() !bool {
	start := v.i
	if v.eat(question_mark) {
		if v.eat_group_name()! {
			if !v.gs.has_in_scope(v.last_str) {
				v.gs.add_to_scope(v.last_str)
				return true
			}
			return v.raise('Duplicate capture group name')
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) consume_atom_escape() !bool {
	if v.consume_backreference()! || v.consume_character_class_escape()!.ok
		|| v.consume_character_escape()! || (v.n_flag && v.consume_k_group_name()!) {
		return true
	}
	if v.strict() || v.unicode_mode {
		return v.raise('Invalid escape')
	}
	return false
}

fn (mut v Validator) consume_backreference() !bool {
	start := v.i
	if v.eat_decimal_escape() {
		n := v.last_int
		if n <= v.num_capturing_parens {
			if v.build {
				v.st_backreference(start - 1, v.i, int(n), '', false)!
			}
			return true
		}
		if v.strict() || v.unicode_mode {
			return v.raise('Invalid escape')
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) escape_set(start int, kind CharacterSetKind, negate bool) !ClassResult {
	v.last_int = -1
	if v.build {
		v.st_escape_character_set(start - 1, v.i, kind, negate)!
	}
	return ClassResult{
		ok: true
	}
}

fn (mut v Validator) consume_character_class_escape() !ClassResult {
	start := v.i
	if v.eat(latin_small_letter_d) {
		return v.escape_set(start, .digit, false)
	}
	if v.eat(latin_capital_letter_d) {
		return v.escape_set(start, .digit, true)
	}
	if v.eat(latin_small_letter_s) {
		return v.escape_set(start, .space, false)
	}
	if v.eat(latin_capital_letter_s) {
		return v.escape_set(start, .space, true)
	}
	if v.eat(latin_small_letter_w) {
		return v.escape_set(start, .word, false)
	}
	if v.eat(latin_capital_letter_w) {
		return v.escape_set(start, .word, true)
	}
	mut negate := false
	if v.unicode_mode && v.ecma() >= 2018 {
		mut ok := v.eat(latin_small_letter_p)
		if !ok {
			negate = v.eat(latin_capital_letter_p)
			ok = negate
		}
		if ok {
			v.last_int = -1
			if v.eat(left_curly_bracket) {
				result := v.eat_unicode_property_value_expression()!
				if result.ok && v.eat(right_curly_bracket) {
					if negate && result.strings {
						return v.raise('Invalid property name')
					}
					if v.build {
						v.st_unicode_property_character_set(start - 1, v.i, result, negate)!
					}
					return ClassResult{
						ok:                  true
						may_contain_strings: result.strings
					}
				}
			}
			return v.raise('Invalid property name')
		}
	}
	return ClassResult{}
}

fn (mut v Validator) consume_character_escape() !bool {
	start := v.i
	if v.eat_control_escape() || v.eat_c_control_letter() || v.eat_zero()
		|| v.eat_hex_escape_sequence()! || v.eat_regexp_unicode_escape_sequence(false)!
		|| (!v.strict() && !v.unicode_mode && v.eat_legacy_octal_escape_sequence())
		|| v.eat_identity_escape() {
		v.on_character(start - 1, v.i, int(v.last_int))!
		return true
	}
	return false
}

fn (mut v Validator) consume_k_group_name() !bool {
	start := v.i
	if v.eat(latin_small_letter_k) {
		if v.eat_group_name()! {
			group_name := v.last_str
			v.backreference_names[group_name] = true
			if v.build {
				v.st_backreference(start - 1, v.i, 0, group_name, true)!
			}
			return true
		}
		return v.raise('Invalid named reference')
	}
	return false
}

fn (mut v Validator) consume_character_class() !ClassResult {
	start := v.i
	if v.eat(left_square_bracket) {
		negate := v.eat(circumflex_accent)
		if v.build {
			v.st_character_class_enter(start, negate, v.unicode_sets_mode)!
		}
		result := v.consume_class_contents()!
		if !v.eat(right_square_bracket) {
			if v.cp1 == -1 {
				return v.raise('Unterminated character class')
			}
			return v.raise('Invalid character in character class')
		}
		if negate && result.may_contain_strings {
			return v.raise('Negated character class may contain strings')
		}
		if v.build {
			v.st_character_class_leave(v.i)!
		}
		return ClassResult{
			ok:                  true
			may_contain_strings: result.may_contain_strings
		}
	}
	return ClassResult{}
}

fn (mut v Validator) consume_class_contents() !ClassResult {
	if v.unicode_sets_mode {
		if v.cp1 == right_square_bracket {
			return ClassResult{
				ok: true
			}
		}
		return v.consume_class_set_expression()
	}
	strict := v.strict() || v.unicode_mode
	for {
		range_start := v.i
		if !v.consume_class_atom()! {
			break
		}
		min := v.last_int
		if !v.eat(hyphen_minus) {
			continue
		}
		v.on_character(v.i - 1, v.i, hyphen_minus)!
		if !v.consume_class_atom()! {
			break
		}
		max := v.last_int
		if min == -1 || max == -1 {
			if strict {
				return v.raise('Invalid character class')
			}
			continue
		}
		if min > max {
			return v.raise('Range out of order in character class')
		}
		if v.build {
			v.st_character_class_range(range_start, v.i)!
		}
	}
	return ClassResult{
		ok: true
	}
}

fn (mut v Validator) consume_class_atom() !bool {
	start := v.i
	cp := v.cp1
	if cp != -1 && cp != reverse_solidus && cp != right_square_bracket {
		v.advance()
		v.last_int = cp
		v.on_character(start, v.i, cp)!
		return true
	}
	if v.eat(reverse_solidus) {
		if v.consume_class_escape()! {
			return true
		}
		if !v.strict() && v.cp1 == latin_small_letter_c {
			v.last_int = reverse_solidus
			v.on_character(start, v.i, reverse_solidus)!
			return true
		}
		if v.strict() || v.unicode_mode {
			return v.raise('Invalid escape')
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) consume_class_escape() !bool {
	start := v.i
	if v.eat(latin_small_letter_b) {
		v.last_int = backspace
		v.on_character(start - 1, v.i, backspace)!
		return true
	}
	if v.unicode_mode && v.eat(hyphen_minus) {
		v.last_int = hyphen_minus
		v.on_character(start - 1, v.i, hyphen_minus)!
		return true
	}
	if !v.strict() && !v.unicode_mode && v.cp1 == latin_small_letter_c {
		cp := v.cp2
		if is_decimal_digit(cp) || cp == low_line {
			v.advance()
			v.advance()
			v.last_int = cp % 0x20
			v.on_character(start - 1, v.i, cp % 0x20)!
			return true
		}
	}
	return v.consume_character_class_escape()!.ok || v.consume_character_escape()!
}

fn (mut v Validator) consume_class_set_expression() !ClassResult {
	start := v.i
	mut may_contain_strings := false
	if v.consume_class_set_character()! {
		if v.consume_class_set_range_from_operator(start)! {
			v.consume_class_union_right(false)!
			return ClassResult{
				ok: true
			}
		}
		may_contain_strings = false
	} else {
		result := v.consume_class_set_operand()!
		if result.ok {
			may_contain_strings = result.may_contain_strings
		} else {
			cp := v.cp1
			if cp == reverse_solidus {
				v.advance()
				return v.raise('Invalid escape')
			}
			if cp == v.cp2 && is_class_set_reserved_double_punctuator_character(cp) {
				return v.raise('Invalid set operation in character class')
			}
			return v.raise('Invalid character in character class')
		}
	}
	if v.eat2(ampersand, ampersand) {
		for v.cp1 != ampersand {
			result := v.consume_class_set_operand()!
			if !result.ok {
				break
			}
			if v.build {
				v.st_class_set_operation(start, v.i, true)!
			}
			if !result.may_contain_strings {
				may_contain_strings = false
			}
			if v.eat2(ampersand, ampersand) {
				continue
			}
			return ClassResult{
				ok:                  true
				may_contain_strings: may_contain_strings
			}
		}
		return v.raise('Invalid character in character class')
	}
	if v.eat2(hyphen_minus, hyphen_minus) {
		for {
			result := v.consume_class_set_operand()!
			if !result.ok {
				break
			}
			if v.build {
				v.st_class_set_operation(start, v.i, false)!
			}
			if v.eat2(hyphen_minus, hyphen_minus) {
				continue
			}
			return ClassResult{
				ok:                  true
				may_contain_strings: may_contain_strings
			}
		}
		return v.raise('Invalid character in character class')
	}
	return v.consume_class_union_right(may_contain_strings)
}

fn (mut v Validator) consume_class_union_right(left_may_contain_strings bool) !ClassResult {
	mut may_contain_strings := left_may_contain_strings
	for {
		start := v.i
		if v.consume_class_set_character()! {
			v.consume_class_set_range_from_operator(start)!
			continue
		}
		result := v.consume_class_set_operand()!
		if result.ok {
			if result.may_contain_strings {
				may_contain_strings = true
			}
			continue
		}
		break
	}
	return ClassResult{
		ok:                  true
		may_contain_strings: may_contain_strings
	}
}

fn (mut v Validator) consume_class_set_range_from_operator(start int) !bool {
	current_start := v.i
	min := v.last_int
	if v.eat(hyphen_minus) {
		if v.consume_class_set_character()! {
			max := v.last_int
			if min == -1 || max == -1 {
				return v.raise('Invalid character class')
			}
			if min > max {
				return v.raise('Range out of order in character class')
			}
			if v.build {
				v.st_character_class_range(start, v.i)!
			}
			return true
		}
		v.rewind(current_start)
	}
	return false
}

fn (mut v Validator) consume_class_set_operand() !ClassResult {
	mut result := v.consume_nested_class()!
	if result.ok {
		return result
	}
	result = v.consume_class_string_disjunction()!
	if result.ok {
		return result
	}
	if v.consume_class_set_character()! {
		return ClassResult{
			ok: true
		}
	}
	return ClassResult{}
}

fn (mut v Validator) consume_nested_class() !ClassResult {
	start := v.i
	if v.eat(left_square_bracket) {
		negate := v.eat(circumflex_accent)
		if v.build {
			v.st_character_class_enter(start, negate, true)!
		}
		result := v.consume_class_contents()!
		if !v.eat(right_square_bracket) {
			return v.raise('Unterminated character class')
		}
		if negate && result.may_contain_strings {
			return v.raise('Negated character class may contain strings')
		}
		if v.build {
			v.st_character_class_leave(v.i)!
		}
		return ClassResult{
			ok:                  true
			may_contain_strings: result.may_contain_strings
		}
	}
	if v.eat(reverse_solidus) {
		result := v.consume_character_class_escape()!
		if result.ok {
			return result
		}
		v.rewind(start)
	}
	return ClassResult{}
}

fn (mut v Validator) consume_class_string_disjunction() !ClassResult {
	start := v.i
	if v.eat3(reverse_solidus, latin_small_letter_q, left_curly_bracket) {
		if v.build {
			v.st_class_string_disjunction_enter(start)!
		}
		mut may_contain_strings := false
		for {
			if v.consume_class_string()! {
				may_contain_strings = true
			}
			if !v.eat(vertical_line) {
				break
			}
		}
		if v.eat(right_curly_bracket) {
			if v.build {
				v.st_leave_container(v.i, .class_string_disjunction)!
			}
			return ClassResult{
				ok:                  true
				may_contain_strings: may_contain_strings
			}
		}
		return v.raise('Unterminated class string disjunction')
	}
	return ClassResult{}
}

// consume_class_string returns mayContainStrings.
fn (mut v Validator) consume_class_string() !bool {
	start := v.i
	mut count := 0
	if v.build {
		v.st_string_alternative_enter(start)!
	}
	for v.cp1 != -1 && v.consume_class_set_character()! {
		count++
	}
	if v.build {
		v.st_leave_container(v.i, .string_alternative)!
	}
	return count != 1
}

fn (mut v Validator) consume_class_set_character() !bool {
	start := v.i
	cp := v.cp1
	if cp != v.cp2 || !is_class_set_reserved_double_punctuator_character(cp) {
		if cp != -1 && !is_class_set_syntax_character(cp) {
			v.last_int = cp
			v.advance()
			v.on_character(start, v.i, cp)!
			return true
		}
	}
	if v.eat(reverse_solidus) {
		if v.consume_character_escape()! {
			return true
		}
		if is_class_set_reserved_punctuator(v.cp1) {
			c := v.cp1
			v.last_int = c
			v.advance()
			v.on_character(start, v.i, c)!
			return true
		}
		if v.eat(latin_small_letter_b) {
			v.last_int = backspace
			v.on_character(start, v.i, backspace)!
			return true
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_group_name() !bool {
	if v.eat(less_than_sign) {
		if v.eat_regexp_identifier_name()! && v.eat(greater_than_sign) {
			return true
		}
		return v.raise('Invalid capture group name')
	}
	return false
}

fn (mut v Validator) eat_regexp_identifier_name() !bool {
	if v.eat_regexp_identifier_start()! {
		mut b := []u8{}
		append_wtf8(mut b, int(v.last_int))
		for v.eat_regexp_identifier_part()! {
			append_wtf8(mut b, int(v.last_int))
		}
		v.last_str = b.bytestr()
		return true
	}
	return false
}

fn (mut v Validator) eat_regexp_identifier_start() !bool {
	start := v.i
	force_u_flag := !v.unicode_mode && v.ecma() >= 2020
	mut cp := v.cp1
	v.advance()
	if cp == reverse_solidus && v.eat_regexp_unicode_escape_sequence(force_u_flag)! {
		cp = int(v.last_int)
	} else if force_u_flag && is_lead_surrogate(cp) && is_trail_surrogate(v.cp1) {
		cp = combine_surrogate_pair(cp, v.cp1)
		v.advance()
	}
	if is_identifier_start_char(cp) {
		v.last_int = cp
		return true
	}
	if v.i != start {
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_regexp_identifier_part() !bool {
	start := v.i
	force_u_flag := !v.unicode_mode && v.ecma() >= 2020
	mut cp := v.cp1
	v.advance()
	if cp == reverse_solidus && v.eat_regexp_unicode_escape_sequence(force_u_flag)! {
		cp = int(v.last_int)
	} else if force_u_flag && is_lead_surrogate(cp) && is_trail_surrogate(v.cp1) {
		cp = combine_surrogate_pair(cp, v.cp1)
		v.advance()
	}
	if is_identifier_part_char(cp) {
		v.last_int = cp
		return true
	}
	if v.i != start {
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_c_control_letter() bool {
	start := v.i
	if v.eat(latin_small_letter_c) {
		if v.eat_control_letter() {
			return true
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_zero() bool {
	if v.cp1 == digit_zero && !is_decimal_digit(v.cp2) {
		v.last_int = 0
		v.advance()
		return true
	}
	return false
}

fn (mut v Validator) eat_control_escape() bool {
	if v.eat(latin_small_letter_f) {
		v.last_int = form_feed
		return true
	}
	if v.eat(latin_small_letter_n) {
		v.last_int = line_feed
		return true
	}
	if v.eat(latin_small_letter_r) {
		v.last_int = carriage_return
		return true
	}
	if v.eat(latin_small_letter_t) {
		v.last_int = character_tabulation
		return true
	}
	if v.eat(latin_small_letter_v) {
		v.last_int = line_tabulation
		return true
	}
	return false
}

fn (mut v Validator) eat_control_letter() bool {
	cp := v.cp1
	if is_latin_letter(cp) {
		v.advance()
		v.last_int = cp % 0x20
		return true
	}
	return false
}

fn (mut v Validator) eat_regexp_unicode_escape_sequence(force_u_flag bool) !bool {
	start := v.i
	u_flag := force_u_flag || v.unicode_mode
	if v.eat(latin_small_letter_u) {
		if (u_flag && v.eat_regexp_unicode_surrogate_pair_escape()) || v.eat_fixed_hex_digits(4)
			|| (u_flag && v.eat_regexp_unicode_code_point_escape()) {
			return true
		}
		if v.strict() || u_flag {
			return v.raise('Invalid unicode escape')
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_regexp_unicode_surrogate_pair_escape() bool {
	start := v.i
	if v.eat_fixed_hex_digits(4) {
		lead := v.last_int
		if is_lead_surrogate_f(lead) && v.eat(reverse_solidus) && v.eat(latin_small_letter_u)
			&& v.eat_fixed_hex_digits(4) {
			trail := v.last_int
			if is_trail_surrogate_f(trail) {
				v.last_int = combine_surrogate_pair(int(lead), int(trail))
				return true
			}
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_regexp_unicode_code_point_escape() bool {
	start := v.i
	if v.eat(left_curly_bracket) && v.eat_hex_digits() && v.eat(right_curly_bracket)
		&& is_valid_unicode(v.last_int) {
		return true
	}
	v.rewind(start)
	return false
}

fn (mut v Validator) eat_identity_escape() bool {
	cp := v.cp1
	if v.is_valid_identity_escape(cp) {
		v.last_int = cp
		v.advance()
		return true
	}
	return false
}

fn (v &Validator) is_valid_identity_escape(cp int) bool {
	if cp == -1 {
		return false
	}
	if v.unicode_mode {
		return is_syntax_character(cp) || cp == solidus
	}
	if v.strict() {
		return !is_id_continue(cp)
	}
	if v.n_flag {
		return !(cp == latin_small_letter_c || cp == latin_small_letter_k)
	}
	return cp != latin_small_letter_c
}

fn (mut v Validator) eat_decimal_escape() bool {
	v.last_int = 0
	mut cp := v.cp1
	if cp >= digit_one && cp <= digit_nine {
		for {
			v.last_int = 10 * v.last_int + f64(cp - digit_zero)
			v.advance()
			cp = v.cp1
			if !(cp >= digit_zero && cp <= digit_nine) {
				break
			}
		}
		return true
	}
	return false
}

fn (mut v Validator) eat_unicode_property_value_expression() !PropertyResult {
	start := v.i
	if v.eat_unicode_property_name() && v.eat(equals_sign) {
		key := v.last_str
		if v.eat_unicode_property_value() {
			value := v.last_str
			if is_valid_unicode_property(v.ecma(), key, value) {
				return PropertyResult{
					ok:        true
					key:       key
					value:     value
					has_value: value != ''
				}
			}
			return v.raise('Invalid property name')
		}
	}
	v.rewind(start)
	if v.eat_lone_unicode_property_name_or_value() {
		name_or_value := v.last_str
		if is_valid_unicode_property(v.ecma(), 'General_Category', name_or_value) {
			return PropertyResult{
				ok:        true
				key:       'General_Category'
				value:     name_or_value
				has_value: name_or_value != ''
			}
		}
		if is_valid_lone_unicode_property(v.ecma(), name_or_value) {
			return PropertyResult{
				ok:  true
				key: name_or_value
			}
		}
		if v.unicode_sets_mode && is_valid_lone_unicode_property_of_string(v.ecma(), name_or_value) {
			return PropertyResult{
				ok:      true
				key:     name_or_value
				strings: true
			}
		}
		return v.raise('Invalid property name')
	}
	return PropertyResult{}
}

fn (mut v Validator) eat_unicode_property_name() bool {
	mut b := []u8{}
	for is_unicode_property_name_character(v.cp1) {
		b << u8(v.cp1)
		v.advance()
	}
	v.last_str = b.bytestr()
	return v.last_str != ''
}

fn (mut v Validator) eat_unicode_property_value() bool {
	mut b := []u8{}
	for is_unicode_property_value_character(v.cp1) {
		b << u8(v.cp1)
		v.advance()
	}
	v.last_str = b.bytestr()
	return v.last_str != ''
}

fn (mut v Validator) eat_lone_unicode_property_name_or_value() bool {
	return v.eat_unicode_property_value()
}

fn (mut v Validator) eat_hex_escape_sequence() !bool {
	start := v.i
	if v.eat(latin_small_letter_x) {
		if v.eat_fixed_hex_digits(2) {
			return true
		}
		if v.unicode_mode || v.strict() {
			return v.raise('Invalid escape')
		}
		v.rewind(start)
	}
	return false
}

fn (mut v Validator) eat_decimal_digits() bool {
	start := v.i
	v.last_int = 0
	for is_decimal_digit(v.cp1) {
		v.last_int = 10 * v.last_int + f64(digit_to_int(v.cp1))
		v.advance()
	}
	return v.i != start
}

fn (mut v Validator) eat_hex_digits() bool {
	start := v.i
	v.last_int = 0
	for is_hex_digit(v.cp1) {
		v.last_int = 16 * v.last_int + f64(digit_to_int(v.cp1))
		v.advance()
	}
	return v.i != start
}

fn (mut v Validator) eat_legacy_octal_escape_sequence() bool {
	if v.eat_octal_digit() {
		n1 := v.last_int
		if v.eat_octal_digit() {
			n2 := v.last_int
			if n1 <= 3 && v.eat_octal_digit() {
				v.last_int = n1 * 64 + n2 * 8 + v.last_int
			} else {
				v.last_int = n1 * 8 + n2
			}
		} else {
			v.last_int = n1
		}
		return true
	}
	return false
}

fn (mut v Validator) eat_octal_digit() bool {
	cp := v.cp1
	if is_octal_digit(cp) {
		v.advance()
		v.last_int = cp - digit_zero
		return true
	}
	v.last_int = 0
	return false
}

fn (mut v Validator) eat_fixed_hex_digits(length int) bool {
	start := v.i
	v.last_int = 0
	for _ in 0 .. length {
		cp := v.cp1
		if !is_hex_digit(cp) {
			v.rewind(start)
			return false
		}
		v.last_int = 16 * v.last_int + f64(digit_to_int(cp))
		v.advance()
	}
	return true
}

fn (mut v Validator) eat_modifiers() bool {
	mut ate := false
	for is_regular_expression_modifier(v.cp1) {
		v.advance()
		ate = true
	}
	return ate
}

fn (mut v Validator) parse_modifiers(start int, end int) !ModifierFlagSet {
	f := v.parse_flags(v.s, start, end)!
	return ModifierFlagSet{
		ignore_case: f.ignore_case
		multiline:   f.multiline
		dot_all:     f.dot_all
	}
}

fn (mut v Validator) parse_flags(source []u16, start int, end int) !FlagSet {
	mut flags := FlagSet{}
	ecma := v.ecma()
	for i in start .. end {
		flag := int(source[i])
		valid := match flag {
			latin_small_letter_g, latin_small_letter_i, latin_small_letter_m { true }
			latin_small_letter_u, latin_small_letter_y { ecma >= 2015 }
			latin_small_letter_s { ecma >= 2018 }
			latin_small_letter_d { ecma >= 2022 }
			latin_small_letter_v { ecma >= 2024 }
			else { false }
		}
		ch := utf16_to_wtf8([source[i]])
		if valid {
			mut dup := false
			match flag {
				latin_small_letter_g {
					dup = flags.global
					flags.global = true
				}
				latin_small_letter_i {
					dup = flags.ignore_case
					flags.ignore_case = true
				}
				latin_small_letter_m {
					dup = flags.multiline
					flags.multiline = true
				}
				latin_small_letter_u {
					dup = flags.unicode
					flags.unicode = true
				}
				latin_small_letter_y {
					dup = flags.sticky
					flags.sticky = true
				}
				latin_small_letter_s {
					dup = flags.dot_all
					flags.dot_all = true
				}
				latin_small_letter_d {
					dup = flags.has_indices
					flags.has_indices = true
				}
				else {
					dup = flags.unicode_sets
					flags.unicode_sets = true
				}
			}
			if dup {
				return v.raise_at("Duplicated flag '${ch}'", start)
			}
		} else {
			return v.raise_at("Invalid flag '${ch}'", start)
		}
	}
	return flags
}
