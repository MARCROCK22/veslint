module regexpp

// SyntaxError is regexpp's RegExpSyntaxError: `message` is byte-identical to the JS message (lone surrogates in
// WTF-8) and `index` is its UTF-16 index.
pub struct SyntaxError {
	Error
pub:
	message string
	index   int
}

pub fn (e SyntaxError) msg() string {
	return e.message
}

// UnknownError is the `new Error("UnknownError")` that regexpp's RegExpParserState throws on an inconsistent event
// sequence (it should not happen for any input).
pub struct UnknownError {
	Error
}

pub fn (e UnknownError) msg() string {
	return 'UnknownError'
}

enum SrcKind {
	literal
	pattern
	flags
}
