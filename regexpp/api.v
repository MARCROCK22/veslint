module regexpp

// Public API. Sources are UTF-16 units (like JS strings) and every offset is a UTF-16 index. Errors are
// SyntaxError (message and index exactly as regexpp's RegExpSyntaxError); the parse functions can also return
// UnknownError where regexpp's parser state would throw `Error("UnknownError")`.

// validate_pattern is `new RegExpValidator(opts).validatePattern(source, start, end, flags)`.
pub fn validate_pattern(source []u16, start int, end int, flags PatternFlags, opts Options) ! {
	mut v := new_validator(opts)
	v.validate_pattern(source, start, end, flags)!
}

// validate_flags is `new RegExpValidator(opts).validateFlags(source, start, end)`.
pub fn validate_flags(source []u16, start int, end int, opts Options) ! {
	mut v := new_validator(opts)
	v.validate_flags(source, start, end)!
}

// validate_literal is `new RegExpValidator(opts).validateLiteral(source, start, end)` (source holds `/pattern/flags`).
pub fn validate_literal(source []u16, start int, end int, opts Options) ! {
	mut v := new_validator(opts)
	v.validate_literal(source, start, end)!
}

// EventsResult holds the validator callbacks seen before validation ended, and the error if it failed.
pub struct EventsResult {
pub:
	events    []ValidatorEvent
	has_error bool
	error     SyntaxError
}

// validate_pattern_events validates like validate_pattern and records onPatternEnter, onPatternLeave and
// onCharacter in call order, including both passes of the "parse twice" that regexpp does when a pattern without
// the n flag has named groups (no-control-regex clears its list on each pattern_enter). Events emitted before a
// syntax error are kept, like the callbacks of a real RegExpValidator.
pub fn validate_pattern_events(source []u16, start int, end int, flags PatternFlags, opts Options) EventsResult {
	mut v := new_validator(opts)
	v.record = true
	v.validate_pattern(source, start, end, flags) or {
		if err is SyntaxError {
			return EventsResult{
				events:    v.events
				has_error: true
				error:     err
			}
		}
		return EventsResult{
			events:    v.events
			has_error: true
			error:     SyntaxError{
				message: err.msg()
				index:   -1
			}
		}
	}
	return EventsResult{
		events: v.events
	}
}

fn new_parser(opts Options) &Validator {
	mut v := new_validator(opts)
	v.build = true
	return v
}

fn (mut v Validator) finish(source []u16, root int) Ast {
	mut a := Ast{
		source: source
		nodes:  v.st.nodes
		root:   root
	}
	a.compact()
	return a
}

fn (v &Validator) current_pattern() !int {
	if v.st.cur < 0 || v.st.nodes[v.st.cur].kind != .pattern {
		return unknown()
	}
	return v.st.cur
}

// parse_pattern is `new RegExpParser(opts).parsePattern(source, start, end, flags)`; the root is the Pattern.
pub fn parse_pattern(source []u16, start int, end int, flags PatternFlags, opts Options) !Ast {
	mut v := new_parser(opts)
	v.validate_pattern(source, start, end, flags)!
	root := v.current_pattern()!
	return v.finish(source, root)
}

// parse_literal is `new RegExpParser(opts).parseLiteral(source, start, end)`; the root is the RegExpLiteral.
pub fn parse_literal(source []u16, start int, end int, opts Options) !Ast {
	mut v := new_parser(opts)
	v.validate_literal(source, start, end)!
	pattern := v.current_pattern()!
	flags := v.st.flags_node
	if flags < 0 {
		return unknown()
	}
	literal := v.add_node(Node{
		kind:    .regexp_literal
		start:   start
		end:     end
		pattern: pattern
		flags:   flags
	})
	v.st.nodes[pattern].parent = literal
	v.st.nodes[flags].parent = literal
	return v.finish(source, literal)
}

// parse_flags is `new RegExpParser(opts).parseFlags(source, start, end)`; the root is the Flags node.
pub fn parse_flags(source []u16, start int, end int, opts Options) !Ast {
	mut v := new_parser(opts)
	v.validate_flags(source, start, end)!
	if v.st.flags_node < 0 {
		return unknown()
	}
	return v.finish(source, v.st.flags_node)
}

// to_utf16 converts a V string (UTF-8, or WTF-8 with lone surrogates) to the UTF-16 units the API takes.
pub fn to_utf16(s string) []u16 {
	return wtf8_to_utf16(s)
}
