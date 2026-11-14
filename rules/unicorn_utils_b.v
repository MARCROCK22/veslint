module rules

import estree

// Helpers of eslint-plugin-unicorn 79.0.0 (rules/utils, rules/fix, rules/ast and rules/shared)
// that are new in it or changed since 64.0.0, for the rules that were brought to 79.0.0 (see
// unicorn_utils.v for the ones that did not change). Offsets are bytes of the source.

// UnbRange is a range of the source, in bytes.
struct UnbRange {
	start int
	end   int
}

// unb_node_range is the range of an ESTree node.
fn unb_node_range(t &estree.EsTree, node int) UnbRange {
	return UnbRange{t.nodes[node].start, t.nodes[node].end}
}

// unb_comment_value is the value of a comment token: its text without `//`, `/*` and `*/`.
fn (c &Checker) unb_comment_value(comment SourceToken) string {
	text := c.src[comment.start..comment.end]
	return match comment.kind {
		.block_comment { text[2..text.len - 2] }
		else { text[2..] }
	}
}

// unb_is_disable_or_enable_directive ports isEslintDisableOrEnableDirective (utils/
// eslint-directive.js): the comment is one of the directives of sourceCode.getDisableDirectives()
// (a `disable`, `enable`, `disable-line` or `disable-next-line` one).
fn (c &Checker) unb_is_disable_or_enable_directive(comment SourceToken) bool {
	if comment.kind == .shebang_comment {
		return false
	}
	label, _, _ := parse_directive(c.unb_comment_value(comment)) or { return false }
	if label !in ['eslint-disable', 'eslint-enable', 'eslint-disable-line', 'eslint-disable-next-line'] {
		return false
	}
	if comment.kind == .line_comment && label !in ['eslint-disable-line', 'eslint-disable-next-line'] {
		return false
	}
	// A multi-line `eslint-disable-line` is a problem, not a directive.
	if label == 'eslint-disable-line' && c.src[comment.start..comment.end].contains_any('\n\r  ') {
		return false
	}
	return true
}

// unb_would_remove_comments ports wouldRemoveComments (utils/comments.js): replacing or removing
// the range would remove a comment that is inside it and outside every preserved range (with
// `ignore_directives`, disable and enable directives do not count).
fn (c &Checker) unb_would_remove_comments(tokens &SourceTokens, replaced UnbRange, preserved []UnbRange, ignore_directives bool) bool {
	for comment in tokens.comments_inside(replaced.start, replaced.end) {
		if comment.end > replaced.end {
			continue
		}
		if preserved.any(comment.start >= it.start && comment.end <= it.end) {
			continue
		}
		if ignore_directives && c.unb_is_disable_or_enable_directive(comment) {
			continue
		}
		return true
	}
	return false
}

// unb_has_non_directive_comment ports hasNonDirectiveComment (utils/comments.js).
fn (c &Checker) unb_has_non_directive_comment(tokens &SourceTokens, replaced UnbRange, preserved []UnbRange) bool {
	return c.unb_would_remove_comments(tokens, replaced, preserved, true)
}

// unb_parenthesized_range is getParenthesizedRange as an UnbRange.
fn (c &Checker) unb_parenthesized_range(t &estree.EsTree, tokens &SourceTokens, node int) UnbRange {
	start, end := c.un_parenthesized_range(t, tokens, node)
	return UnbRange{start, end}
}
