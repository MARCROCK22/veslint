module rules

import vue

// The template token store (parserServices.getTemplateBodyTokenStore(): ESLint's TokenStore on
// the document's tokens and comments, vue-eslint-parser's copy of it). The document's tokens and
// comments are both sorted by start. `include_comments` is TokenStore's `includeComments: true`,
// which also gives the HTML comments; the comments-only queries of the original
// (getCommentsBefore/After/Inside) give only `Line` and `Block` comments (vue_is_js_comment).

// vue_lower_bound is the index of the first token that starts at or after `offset`.
fn vue_lower_bound(tokens []vue.Token, offset int) int {
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

// vue_tokens_in is getTokens(node): the tokens inside [start, end).
fn (c &Checker) vue_tokens_in(start int, end int) []vue.Token {
	tokens := c.vue.doc.tokens
	mut out := []vue.Token{}
	for i := vue_lower_bound(tokens, start); i < tokens.len && tokens[i].start < end; i++ {
		if tokens[i].end <= end {
			out << tokens[i]
		}
	}
	return out
}

// vue_tokens_with_comments_in is getTokens(node, {includeComments: true}).
fn (c &Checker) vue_tokens_with_comments_in(start int, end int) []vue.Token {
	mut out := c.vue_tokens_in(start, end)
	comments := c.vue.doc.comments
	for i := vue_lower_bound(comments, start); i < comments.len && comments[i].start < end; i++ {
		if comments[i].end <= end {
			out << comments[i]
		}
	}
	out.sort(a.start < b.start)
	return out
}

// vue_first_token_in is getFirstToken(node).
fn (c &Checker) vue_first_token_in(start int, end int) ?vue.Token {
	tokens := c.vue.doc.tokens
	i := vue_lower_bound(tokens, start)
	if i < tokens.len && tokens[i].end <= end {
		return tokens[i]
	}
	return none
}

// vue_last_token_in is getLastToken(node).
fn (c &Checker) vue_last_token_in(start int, end int) ?vue.Token {
	tokens := c.vue.doc.tokens
	mut i := vue_lower_bound(tokens, end) - 1
	for i >= 0 && tokens[i].end > end {
		i--
	}
	if i >= 0 && tokens[i].start >= start {
		return tokens[i]
	}
	return none
}

// vue_token_before is getTokenBefore(node): the last token that ends at or before `offset`
// (comments too with `include_comments`).
fn (c &Checker) vue_token_before(offset int, include_comments bool) ?vue.Token {
	mut best := ?vue.Token(none)
	tokens := c.vue.doc.tokens
	mut i := vue_lower_bound(tokens, offset) - 1
	for i >= 0 && tokens[i].end > offset {
		i--
	}
	if i >= 0 {
		best = tokens[i]
	}
	if include_comments {
		comments := c.vue.doc.comments
		mut j := vue_lower_bound(comments, offset) - 1
		for j >= 0 && comments[j].end > offset {
			j--
		}
		if j >= 0 {
			if b := best {
				if comments[j].start > b.start {
					best = comments[j]
				}
			} else {
				best = comments[j]
			}
		}
	}
	return best
}

// vue_token_after is getTokenAfter(node): the first token that starts at or after `offset`
// (comments too with `include_comments`).
fn (c &Checker) vue_token_after(offset int, include_comments bool) ?vue.Token {
	mut best := ?vue.Token(none)
	tokens := c.vue.doc.tokens
	i := vue_lower_bound(tokens, offset)
	if i < tokens.len {
		best = tokens[i]
	}
	if include_comments {
		comments := c.vue.doc.comments
		j := vue_lower_bound(comments, offset)
		if j < comments.len {
			if b := best {
				if comments[j].start < b.start {
					best = comments[j]
				}
			} else {
				best = comments[j]
			}
		}
	}
	return best
}

// vue_is_js_comment: a `Line` or `Block` comment (what isCommentToken takes), not an HTML one.
fn vue_is_js_comment(t vue.Token) bool {
	return t.typ in ['Line', 'Block', 'Shebang']
}
