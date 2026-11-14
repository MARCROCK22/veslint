module rules

import estree
import json2
import treesitter { Ident }
import time

// Port of the `unicorn/relative-url-style` rule of eslint-plugin-unicorn 79.0.0, option `never`
// (the default) or `always`, with its fix and suggestion: the JavaScript listeners (`new URL()`,
// `URL.canParse()`, `URL.parse()` and the attributes of native JSX elements); its CSS, HTML and
// Markdown listeners do not apply to TypeScript. Whether `./` can be added or removed runs the
// URL Standard (rules/whatwg_url.v); a URL with a domain that needs UTS #46 (non-ASCII, or a
// label that starts with `xn--`), which that file does not port, is taken as unsafe.

const rus_messages = {
	'never':  'Remove the `./` prefix from the relative URL.'
	'always': 'Add a `./` prefix to the relative URL.'
	'remove': 'Remove leading `./`.'
}

const rus_test_url_bases = ['https://example.com/a/b/', 'https://example.com/a/b.html',
	'file:///a/b.html']

const rus_html_url_attributes = ['href', 'src', 'poster', 'srcset', 'imagesrcset', 'action',
	'formaction', 'cite']

const rus_jsx_url_attributes = ['href', 'src', 'poster', 'srcSet', 'imageSrcSet', 'action', 'formAction',
	'cite']

// rus_options reads the option: 'never' (the default) or 'always'.
fn rus_options(options []json2.Any) !string {
	if options.len == 0 {
		return 'never'
	}
	value := options[0]
	return if value is string { value } else { 'never' }
}

// rus_is_safe_to_add_dot_slash ports isSafeToAddDotSlash: for every base.
fn rus_is_safe_to_add_dot_slash(url string, bases []string) bool {
	return bases.all(wu_is_safe_to_add_dot_slash(url, it) or { false })
}

// rus_is_safe_to_remove_dot_slash ports isSafeToRemoveDotSlash.
fn rus_is_safe_to_remove_dot_slash(url string, bases []string) bool {
	rest := if url.len >= 2 { url[2..] } else { '' }
	return bases.all(wu_is_safe_to_add_dot_slash(rest, it) or { false })
}

// rus_is_dot_relative tells whether a URL matches /^\.\.?(?:[#/?\\]|$)/u.
fn rus_is_dot_relative(url string) bool {
	mut i := 0
	if i < url.len && url[i] == `.` {
		i++
	} else {
		return false
	}
	if i < url.len && url[i] == `.` {
		i++
	}
	return i == url.len || url[i] in [`#`, `/`, `?`, `\\`]
}

struct RusContext {
	style string
}

// rus_url_problem ports getUrlProblem: the report of `node` (with `loc` when it is not the node's)
// when the URL that starts at `start` in the source has a `./` to remove, or needs one.
fn (c &Checker) rus_url_problem(ctx RusContext, stmt Ident, url string, start int, bases []string) ?Finding {
	if ctx.style == 'never' {
		if !c.src[start..].starts_with('./') || !rus_is_safe_to_remove_dot_slash(url, bases) {
			return none
		}
	} else if rus_is_dot_relative(url) || url.starts_with('/')
		|| !rus_is_safe_to_add_dot_slash(url, bases) {
		return none
	}
	return Finding{
		stmt:       stmt
		message_id: ctx.style
		has_fix:    true
		fix:        if ctx.style == 'never' {
			fix_remove_range(start, start + 2)
		} else {
			fix_insert_at(start, './')
		}
	}
}

fn rus_is_html_whitespace(c u8) bool {
	return c in [`\t`, `\n`, `\f`, `\r`, ` `]
}

// rus_html_attribute_problems ports getHtmlAttributeProblems: the problems of an attribute whose
// raw value starts at `start`, reported on `node` at the URL of each problem.
fn (c &Checker) rus_html_attribute_problems(ctx RusContext, name string, raw string, start int) []Finding {
	if name !in rus_html_url_attributes || raw == '' {
		return []
	}
	mut out := []Finding{}
	if name == 'srcset' || name == 'imagesrcset' {
		if html_decode_attribute(raw) != raw {
			return []
		}
		// A leading comma would become a candidate separator if the prefix were removed.
		for candidate in rus_srcset_candidates(raw) {
			if candidate.value.starts_with('./,') {
				continue
			}
			at := start + candidate.start
			if finding := c.rus_url_problem(ctx, c.position_range(at, at + candidate.value.len),
				candidate.value, at, rus_test_url_bases)
			{
				out << finding
			}
		}
		return out
	}
	mut value_start := 0
	mut value_end := raw.len
	for value_start < value_end && rus_is_html_whitespace(raw[value_start]) {
		value_start++
	}
	for value_end > value_start && rus_is_html_whitespace(raw[value_end - 1]) {
		value_end--
	}
	value := raw[value_start..value_end]
	url := html_decode_attribute(value)
	if url != js_trim(url) {
		return []
	}
	at := start + value_start
	if finding := c.rus_url_problem(ctx, c.position_range(at, at + value.len), url, at,
		rus_test_url_bases)
	{
		out << finding
	}
	return out
}

fn (mut c Checker) lint_unicorn_relative_url_style(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut findings := []Finding{}
	t := c.es_tree(root, abs_path) or { return findings }
	ctx := RusContext{
		style: rus_options(c.rule_options(unicorn_relative_url_style))!
	}
	for node in 0 .. t.nodes.len {
		match t.typ(node) {
			.jsx_attribute {
				stats.checked++
				findings << c.rus_jsx_attribute(ctx, t, node)
			}
			.new_expression, .call_expression {
				stats.checked++
				if finding := c.rus_url_call(root, ctx, t, node) {
					findings << finding
				}
			}
			else {}
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

// rus_jsx_attribute ports the JSXAttribute listener: the URL attributes of native elements.
fn (c &Checker) rus_jsx_attribute(ctx RusContext, t &estree.EsTree, node int) []Finding {
	opening := t.nodes[node].parent
	if opening < 0 {
		return []
	}
	tag := t.node(opening, .name) or { return [] }
	name := t.node(node, .name) or { return [] }
	tag_name := t.string_of(tag, .name) or { '' }
	attribute := t.string_of(name, .name) or { '' }
	if t.typ(tag) != .jsx_identifier || !rus_is_native_tag(tag_name)
		|| t.typ(name) != .jsx_identifier || attribute !in rus_jsx_url_attributes {
		return []
	}
	value := t.node(node, .value) or { return [] }
	if t.typ(value) == .jsx_expression_container {
		expression := t.node(value, .expression) or { return [] }
		if attribute in ['srcSet', 'imageSrcSet'] || (!un_is_string_literal(t, expression)
			&& !(t.typ(expression) == .template_literal
				&& (t.list(expression, .expressions) or { []int{} }).len == 0)) {
			return []
		}
		url := un_static_string_value(t, expression) or { return [] }
		if finding := c.rus_url_problem(ctx, c.es_tree_position(t, expression), url,
			t.nodes[expression].start + 1, rus_test_url_bases)
		{
			return [finding]
		}
		return []
	}
	if !un_is_string_literal(t, value) {
		return []
	}
	raw := c.src[t.nodes[value].start + 1..t.nodes[value].end - 1]
	// JSX parsers and HTML can decode character references differently.
	if html_decode_attribute(raw) != t.get(value, .value) as string {
		return []
	}
	return c.rus_html_attribute_problems(ctx, attribute.to_lower(), raw, t.nodes[value].start + 1)
}

// rus_is_native_tag tells whether the name of an element matches /^[a-z][\dA-Za-z]*$/u.
fn rus_is_native_tag(name string) bool {
	return name.len > 0 && name[0] >= `a` && name[0] <= `z`
		&& name.bytes().all(html_is_alphanumeric(it))
}

// rus_url_call ports the NewExpression and CallExpression listener: `new URL(url, base)`,
// `URL.canParse(url, base)` and `URL.parse(url, base)`.
fn (mut c Checker) rus_url_call(root C.TSNode, ctx RusContext, t &estree.EsTree, node int) ?Finding {
	if !un_is_new(t, node, names: ['URL'], arguments_length: 2) && !un_is_method_call(t, node,
		objects:          ['URL']
		methods:          ['canParse', 'parse']
		arguments_length: 2
		computed:         false
		optional_call:    false
		optional_member:  false
	) {
		return none
	}
	args := t.list(node, .arguments) or { return none }
	mut argument := args[0]
	for un_is_ts_expression_wrapper(t, argument) {
		if t.typ(argument) == .ts_satisfies_expression {
			return none
		}
		argument = t.node(argument, .expression) or { return none }
	}
	if !un_is_string_literal(t, argument) && t.typ(argument) != .template_literal {
		return none
	}
	start := t.nodes[argument].start + 1 // After the quote.
	// Template literals are not always safe to remove `./` from, but report those starting with
	// `./`.
	if t.typ(argument) == .template_literal
		&& (t.list(argument, .expressions) or { []int{} }).len > 0 {
		quasis := t.list(argument, .quasis) or { return none }
		first := t.get(quasis[0], .value)
		if ctx.style != 'never' || first !is estree.TemplateValue
			|| !(first as estree.TemplateValue).raw.starts_with('./') {
			return none
		}
		return Finding{
			stmt:        c.es_tree_position(t, argument)
			message_id:  ctx.style
			suggestions: [
				Suggestion{
					message_id: 'remove'
					fix:        fix_remove_range(start, start + 2)
				},
			]
		}
	}
	url := un_static_string_value(t, argument)?
	base := c.unb_static_value_if_no_side_effects(root, t, args[1])
	bases := if b := base {
		if b.value.kind == .string_ {
			[stv_units_string(b.value.units)]
		} else {
			rus_test_url_bases
		}
	} else {
		rus_test_url_bases
	}
	return c.rus_url_problem(ctx, c.es_tree_position(t, argument), url, start, bases)
}

// RusCandidate is an image candidate of a srcset: its URL and where it starts in the value.
struct RusCandidate {
	value string
	start int
}

// RusSrcsetCharacter is a character of a srcset, decoded when it is a character reference.
struct RusSrcsetCharacter {
	value string
	end   int
}

// rus_numeric_reference_end ports getNumericCharacterReferenceEnd of
// shared/get-srcset-candidates.js.
fn rus_numeric_reference_end(value string, index int) ?int {
	mut end := index + 2
	is_hexadecimal := end < value.len && (value[end] | 0x20) == `x`
	if is_hexadecimal {
		end++
	}
	digit_start := end
	for end < value.len && (html_is_digit(value[end]) || (is_hexadecimal
		&& (value[end] | 0x20) >= `a` && (value[end] | 0x20) <= `f`)) {
		end++
	}
	if end == digit_start {
		return none
	}
	return if end < value.len && value[end] == `;` { end + 1 } else { end }
}

// rus_srcset_character ports getSrcsetCharacter.
fn rus_srcset_character(value string, index int) RusSrcsetCharacter {
	literal := RusSrcsetCharacter{
		value: value[index..index + 1]
		end:   index + 1
	}
	if value[index] != `&` {
		return literal
	}
	mut end := -1
	if index + 1 < value.len && value[index + 1] == `#` {
		end = rus_numeric_reference_end(value, index) or { -1 }
	} else {
		// A named character reference is `&` + letters and digits + `;`, within 64 characters.
		mut i := index + 1
		limit := int_min(value.len, index + 64)
		for i < limit && html_is_alphanumeric(value[i]) {
			i++
		}
		if i > index + 1 && i < limit && value[i] == `;` {
			end = i + 1
		}
	}
	if end < 0 {
		return literal
	}
	source := value[index..end]
	decoded := html_decode_attribute(source)
	if decoded == source {
		return literal
	}
	return RusSrcsetCharacter{
		value: decoded
		end:   end
	}
}

fn rus_is_srcset_whitespace(character string) bool {
	return character.len == 1 && rus_is_html_whitespace(character[0])
}

// rus_skip_srcset_separators ports skipSrcsetSeparators.
fn rus_skip_srcset_separators(value string, from int) int {
	mut index := from
	for index < value.len {
		character := rus_srcset_character(value, index)
		if character.value != ',' && !rus_is_srcset_whitespace(character.value) {
			return index
		}
		index = character.end
	}
	return value.len
}

// rus_srcset_candidate ports getSrcsetCandidate: the end of the URL, where the search goes on and
// whether the URL ended with commas.
fn rus_srcset_candidate(value string, from int) (int, int, bool) {
	mut index := from
	mut end := from
	mut trailing_comma_start := -1
	for index < value.len {
		character := rus_srcset_character(value, index)
		if rus_is_srcset_whitespace(character.value) {
			break
		}
		if character.value == ',' {
			if trailing_comma_start < 0 {
				trailing_comma_start = index
			}
		} else {
			trailing_comma_start = -1
		}
		end = character.end
		index = character.end
	}
	return if trailing_comma_start >= 0 { trailing_comma_start } else { end }, index, trailing_comma_start >= 0
}

// rus_next_srcset_candidate_start ports getNextSrcsetCandidateStart.
fn rus_next_srcset_candidate_start(value string, from int) int {
	mut index := from
	mut parenthesis_depth := 0
	for index < value.len {
		character := rus_srcset_character(value, index)
		index = character.end
		if character.value == '(' {
			parenthesis_depth++
		} else if character.value == ')' && parenthesis_depth > 0 {
			parenthesis_depth--
		} else if character.value == ',' && parenthesis_depth == 0 {
			return index
		}
	}
	return value.len
}

// rus_srcset_candidates ports getSrcsetCandidates of shared/get-srcset-candidates.js: the URLs of
// a srcset attribute.
fn rus_srcset_candidates(value string) []RusCandidate {
	mut candidates := []RusCandidate{}
	mut index := 0
	for index < value.len {
		index = rus_skip_srcset_separators(value, index)
		start := index
		end, next, has_trailing_comma := rus_srcset_candidate(value, index)
		if end > start {
			candidates << RusCandidate{
				value: value[start..end]
				start: start
			}
		}
		index = if has_trailing_comma { next } else { rus_next_srcset_candidate_start(value, next) }
	}
	return candidates
}
