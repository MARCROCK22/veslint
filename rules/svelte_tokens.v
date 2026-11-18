module rules

import svelte

// The token store of a .svelte file for the svelte/* rules (context.sourceCode's TokenStore on
// svelte-eslint-parser's tokens and comments of the whole file: the script's, the markup's and
// the template expressions'), on doc.tokens and doc.comments, both sorted by start, with file
// offsets. `include_comments` is TokenStore's `includeComments: true`.

// sv_lower_bound is the index of the first token that starts at or after `offset`.
fn sv_lower_bound(tokens []svelte.Token, offset int) int {
	mut lo := 0
	mut hi := tokens.len
	for lo < hi {
		mid := (lo + hi) / 2
		if tokens[mid].start < offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// sv_upper_end is the number of tokens that end at or before `offset` (the tokens do not overlap,
// so their ends are sorted too).
fn sv_upper_end(tokens []svelte.Token, offset int) int {
	mut lo := 0
	mut hi := tokens.len
	for lo < hi {
		mid := (lo + hi) / 2
		if tokens[mid].end <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// sv_is_comment: a token of doc.comments (a `Line` or `Block` comment).
fn sv_is_comment(t svelte.Token) bool {
	return t.typ == 'Line' || t.typ == 'Block'
}

// sv_tokens_in is getTokens(node) of the range [start, end) (with comments: the comments inside
// too, in order).
fn (c &Checker) sv_tokens_in(start int, end int, include_comments bool) []svelte.Token {
	doc := c.svelte.doc
	mut out := []svelte.Token{}
	for i := sv_lower_bound(doc.tokens, start); i < doc.tokens.len && doc.tokens[i].start < end; i++ {
		if doc.tokens[i].end <= end {
			out << doc.tokens[i]
		}
	}
	if include_comments {
		mut any := false
		for i := sv_lower_bound(doc.comments, start); i < doc.comments.len
			&& doc.comments[i].start < end; i++ {
			if doc.comments[i].end <= end {
				out << doc.comments[i]
				any = true
			}
		}
		if any {
			out.sort(a.start < b.start)
		}
	}
	return out
}

// sv_first_token is getFirstToken(node) of the range [start, end).
fn (c &Checker) sv_first_token(start int, end int) ?svelte.Token {
	tokens := c.svelte.doc.tokens
	i := sv_lower_bound(tokens, start)
	if i < tokens.len && tokens[i].end <= end {
		return tokens[i]
	}
	return none
}

// sv_last_token is getLastToken(node) of the range [start, end).
fn (c &Checker) sv_last_token(start int, end int) ?svelte.Token {
	tokens := c.svelte.doc.tokens
	i := sv_upper_end(tokens, end) - 1
	if i >= 0 && tokens[i].start >= start {
		return tokens[i]
	}
	return none
}

// sv_token_after is getTokenAfter of a node or token that ends at `offset`.
fn (c &Checker) sv_token_after(offset int, include_comments bool) ?svelte.Token {
	doc := c.svelte.doc
	i := sv_lower_bound(doc.tokens, offset)
	mut best := if i < doc.tokens.len { ?svelte.Token(doc.tokens[i]) } else { ?svelte.Token(none) }
	if include_comments {
		j := sv_lower_bound(doc.comments, offset)
		if j < doc.comments.len {
			if b := best {
				if doc.comments[j].start < b.start {
					best = doc.comments[j]
				}
			} else {
				best = doc.comments[j]
			}
		}
	}
	return best
}

// sv_token_before is getTokenBefore of a node or token that starts at `offset`.
fn (c &Checker) sv_token_before(offset int, include_comments bool) ?svelte.Token {
	doc := c.svelte.doc
	i := sv_upper_end(doc.tokens, offset) - 1
	mut best := if i >= 0 { ?svelte.Token(doc.tokens[i]) } else { ?svelte.Token(none) }
	if include_comments {
		j := sv_upper_end(doc.comments, offset) - 1
		if j >= 0 {
			if b := best {
				if doc.comments[j].start > b.start {
					best = doc.comments[j]
				}
			} else {
				best = doc.comments[j]
			}
		}
	}
	return best
}

// sv_tokens_between is getTokensBetween of a node or token ending at `left_end` and one starting
// at `right_start`.
fn (c &Checker) sv_tokens_between(left_end int, right_start int, include_comments bool) []svelte.Token {
	return c.sv_tokens_in(left_end, right_start, include_comments)
}

// sv_is_punctuator: the token is a punctuator with that value (eslint-utils' isOpeningParenToken
// and the like).
fn sv_is_punctuator(t svelte.Token, value string) bool {
	return t.typ == 'Punctuator' && t.value == value
}

// sv_token_loc_start and sv_token_loc_end are where a token's `loc` starts and ends (bytes of the
// file): its range, but where svelte-eslint-parser keeps a stale loc (Token.loc_start/loc_end).
fn sv_token_loc_start(t svelte.Token) int {
	return if t.loc_start >= 0 { t.loc_start } else { t.start }
}

fn sv_token_loc_end(t svelte.Token) int {
	return if t.loc_end >= 0 { t.loc_end } else { t.end }
}

// sv_line is the line (from 1) of svelte-eslint-parser's location of a byte offset.
fn (c &Checker) sv_line(offset int) int {
	return c.svelte.doc.loc(offset).line
}

// sv_snode_loc_end is where a Svelte node's `loc` ends.
fn (c &Checker) sv_snode_loc_end(i int) int {
	n := &c.svelte.doc.nodes[i]
	return if n.loc_end >= 0 { n.loc_end } else { n.end }
}
