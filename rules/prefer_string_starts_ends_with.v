module rules

import json2
import time
import treesitter { Ident, children, named_children, node_end, node_field, node_kind, node_start, nodes_of_kinds, position_of }

// Port of the `prefer-string-starts-ends-with` rule of typescript-eslint 8.62.0, with its option
// and its fixes.

const pssew_messages = {
	'preferEndsWith':   "Use the 'String#endsWith' method instead."
	'preferStartsWith': "Use 'String#startsWith' method instead."
}

struct PssewOptions {
	allow_single_element_equality bool // allowSingleElementEquality: 'always'
}

fn pssew_options(options []json2.Any) !PssewOptions {
	o := option_object(prefer_string_starts_ends_with, options, ['allowSingleElementEquality'])!
	return PssewOptions{
		allow_single_element_equality: o.string_value('allowSingleElementEquality', [
			'always',
			'never',
		])! == 'always'
	}
}

// PssewCandidate is a report whose last condition, when `typed`, is that `object` has a string
// type.
struct PssewCandidate {
	report     Ident
	message_id string
	object     C.TSNode
	typed      bool = true
	fixes      []Fix // what the fixer yields; none when it returns null
}

// PssewRegexp is what parseRegExp gives: the form and the text, as JSON.stringify writes it.
struct PssewRegexp {
	starts bool
	text   string
}

fn (mut c Checker) lint_prefer_string_starts_ends_with(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	mut sw := time.new_stopwatch()
	o := pssew_options(c.rule_options(prefer_string_starts_ends_with))!
	mut candidates := []PssewCandidate{}
	for n in c.nodes_of_kinds(root, ['binary_expression', 'call_expression'], []string{}) {
		if node_kind(n) == 'call_expression' {
			c.pssew_test(n, mut candidates)
			continue
		}
		if estree_binary_kind(n) != 'BinaryExpression' {
			continue
		}
		left := unwrap_parens(node_field(n, 'left') or { continue })
		if node_kind(left) == 'subscript_expression' {
			c.pssew_single_element(left, n, none, o, mut candidates)
			continue
		}
		args := call_arguments(left) or { continue }
		callee := unwrap_parens(node_field(left, 'function') or { continue })
		if node_kind(callee) == 'member_expression' && !is_estree_chain_root(callee) {
			property := node_field(callee, 'property') or { continue }
			name := if node_kind(property) == 'property_identifier' {
				c.identifier_name(property)
			} else {
				''
			}
			match name {
				'charAt' { c.pssew_single_element(callee, n, left, o, mut candidates) }
				'indexOf' { c.pssew_index_of(callee, n, left, args, mut candidates) }
				'lastIndexOf' { c.pssew_last_index_of(callee, n, left, args, mut candidates) }
				'match' { c.pssew_match(callee, n, left, args, mut candidates) }
				else {}
			}
		}
		// 'BinaryExpression > CallExpression.left > MemberExpression': the callee or an argument.
		mut members := [callee]
		members << args.map(unwrap_parens(it))
		for member in members {
			if is_member(member) && !is_estree_chain_root(member) {
				c.pssew_slice(member, n, args, mut candidates)
			}
		}
	}
	c.resolve_spans(candidates.filter(it.typed).map(node_span(it.object)), abs_path, mut
		stats)!
	stats.types_ms += ms(sw.elapsed())
	sw.restart()
	mut findings := []Finding{}
	for cand in candidates {
		mut report := !cand.typed
		if cand.typed {
			t := c.node_type(cand.object) or { continue }
			report = c.type_name(t, 0)! == 'string'
		}
		if report {
			findings << c.with_fixes(Finding{
				stmt:       cand.report
				message_id: cand.message_id
			}, cand.fixes)!
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	stats.checked += candidates.len
	return findings
}

fn pssew_message(starts bool) string {
	return if starts { 'preferStartsWith' } else { 'preferEndsWith' }
}

fn pssew_is_equality(binary C.TSNode) bool {
	return operator_of(binary) in ['==', '===', '!=', '!==']
}

// pssew_single_element handles `foo[0] === "a"`, `foo.charAt(0) === "a"` and their last-index
// variants; `call` is the charAt call.
fn (mut c Checker) pssew_single_element(member C.TSNode, binary C.TSNode, call ?C.TSNode, o PssewOptions, mut out []PssewCandidate) {
	mut index := ?C.TSNode(none)
	if charat := call {
		args := call_arguments(charat) or { return }
		if args.len == 1 {
			index = args[0]
		}
	} else {
		index = member_property(member)
	}
	index_node := index or { return }
	if !pssew_is_equality(binary) {
		return
	}
	object := unwrap_parens(node_field(member, 'object') or { return })
	is_ends := c.pssew_is_last_index(index_node, object)
	if o.allow_single_element_equality && is_ends {
		return
	}
	is_starts := !is_ends && c.pssew_is_number(index_node, 0)
	if (o.allow_single_element_equality && is_starts) || (!is_starts && !is_ends) {
		return
	}
	// Don't fix if it can change the behavior: the right side must be one character (isCharacter).
	mut fixes := []Fix{}
	character := c.get_static_value(node_field(binary, 'right') or { return })
	if character.found && character.value.kind == .string_ && character.value.units.len == 1 {
		fixes = c.pssew_fix_with_right(binary, is_starts, is_optional_element(member))
	}
	out << PssewCandidate{
		report:     position_of(binary)
		message_id: pssew_message(is_starts)
		object:     object
		fixes:      fixes
	}
}

// pssew_index_of handles `foo.indexOf('bar') === 0`.
fn (mut c Checker) pssew_index_of(member C.TSNode, binary C.TSNode, call C.TSNode, args []C.TSNode, mut out []PssewCandidate) {
	if args.len != 1 || !pssew_is_equality(binary)
		|| !c.pssew_is_number(node_field(binary, 'right') or { return }, 0) {
		return
	}
	out << PssewCandidate{
		report:     position_of(binary)
		message_id: 'preferStartsWith'
		object:     unwrap_parens(node_field(member, 'object') or { return })
		fixes:      c.pssew_fix_with_argument(binary, call, member, true)
	}
}

// pssew_last_index_of handles `foo.lastIndexOf(bar) === foo.length - bar.length`.
fn (mut c Checker) pssew_last_index_of(member C.TSNode, binary C.TSNode, call C.TSNode, args []C.TSNode, mut out []PssewCandidate) {
	if args.len != 1 || !pssew_is_equality(binary) {
		return
	}
	right := unwrap_parens(node_field(binary, 'right') or { return })
	if estree_binary_kind(right) != 'BinaryExpression' || operator_of(right) != '-' {
		return
	}
	object := unwrap_parens(node_field(member, 'object') or { return })
	if !c.pssew_is_length(node_field(right, 'left') or { return }, object)
		|| !c.pssew_is_length(node_field(right, 'right') or { return }, args[0]) {
		return
	}
	out << PssewCandidate{
		report:     position_of(binary)
		message_id: 'preferEndsWith'
		object:     object
		fixes:      c.pssew_fix_with_argument(binary, call, member, false)
	}
}

// pssew_match handles `foo.match(/^bar/) === null`, reported at the call.
fn (mut c Checker) pssew_match(member C.TSNode, binary C.TSNode, call C.TSNode, args []C.TSNode, mut out []PssewCandidate) {
	right := c.get_static_value(node_field(binary, 'right') or { return })
	if !right.found || !stv_is_nullish(right.value) || args.len != 1 {
		return
	}
	parsed := c.pssew_parse_regexp(args[0]) or { return }
	// The fixer: `!` unless the operator has one, the property becomes the method, the argument the
	// text and the comparison goes.
	mut fixes := []Fix{}
	if property_start := c.pssew_property_start(member) {
		if !operator_of(binary).starts_with('!') {
			fixes << fix_insert_before(binary, '!')
		}
		fixes << fix_replace_range(property_start, node_end(member), pssew_method(parsed.starts,
			is_optional_element(member)))
		fixes << fix_replace(unwrap_parens(args[0]), parsed.text)
		fixes << fix_remove_range(node_end(call), node_end(binary))
	}
	out << PssewCandidate{
		report:     position_of(call)
		message_id: pssew_message(parsed.starts)
		object:     unwrap_parens(node_field(member, 'object') or { return })
		fixes:      fixes
	}
}

// pssew_slice handles `foo.slice(0, 3) === 'bar'`, `foo.substring(foo.length - 3) === 'bar'` and
// the like.
fn (mut c Checker) pssew_slice(member C.TSNode, binary C.TSNode, args []C.TSNode, mut out []PssewCandidate) {
	if !c.is_static_member_access_of_value(member, ['slice', 'substring']) || !pssew_is_equality(binary) {
		return
	}
	object := unwrap_parens(node_field(member, 'object') or { return })
	right := node_field(binary, 'right') or { return }
	mut is_ends := false
	mut is_starts := false
	if args.len == 1 {
		is_ends = c.pssew_is_length_ahead_of_end(args[0], right, object)
	} else if args.len == 2 {
		if c.pssew_is_number(args[0], 0) && c.pssew_is_length(args[1], right) {
			is_starts = true
		} else if (c.pssew_is_length(args[1], object) || c.pssew_is_number(args[1], 0))
			&& c.pssew_is_length_ahead_of_end(args[0], right, object) {
			is_ends = true
		}
	}
	if !is_starts && !is_ends {
		return
	}
	out << PssewCandidate{
		report:     position_of(binary)
		message_id: pssew_message(is_starts)
		object:     object
		fixes:      c.pssew_slice_fixes(member, binary, args, object, is_starts)
	}
}

// pssew_slice_fixes ports the fixer of the slice and substring reports, which gives up when the
// fix could change the behavior.
fn (mut c Checker) pssew_slice_fixes(member C.TSNode, binary C.TSNode, args []C.TSNode, object C.TSNode, is_starts bool) []Fix {
	right := node_field(binary, 'right') or { return []Fix{} }
	// `==` and `!=` are only fixed against a string literal.
	if operator_of(binary).len == 2 && node_kind(unwrap_parens(right)) != 'string' {
		return []Fix{}
	}
	// The code being checked is likely a mistake: unequal lengths of the strings being compared,
	// or reliance on substring reading a negative index as 0.
	if is_starts {
		if !c.pssew_is_length(args[1], right) {
			return []Fix{}
		}
	} else {
		position := unwrap_parens(args[0])
		// negativeIndexSupported: `node.property.name === 'slice'`.
		property := member_property(member) or { return []Fix{} }
		is_slice := node_kind(property) in ['property_identifier', 'identifier']
			&& c.identifier_name(property) == 'slice'
		valid := if estree_binary_kind(position) == 'BinaryExpression' && operator_of(position) == '-' {
			c.pssew_is_length(node_field(position, 'left') or { return []Fix{} }, object)
				&& c.pssew_is_length(node_field(position, 'right') or { return []Fix{} }, right)
		} else if is_slice && node_kind(position) == 'unary_expression'
			&& operator_of(position) == '-' {
			c.pssew_is_length(node_field(position, 'argument') or { return []Fix{} }, right)
		} else {
			false
		}
		if !valid {
			return []Fix{}
		}
	}
	return c.pssew_fix_with_right(binary, is_starts, is_optional_element(member))
}

// pssew_method is the method access that replaces the property: `.startsWith`, `?.endsWith`…
fn pssew_method(starts bool, optional bool) string {
	dot := if optional { '?.' } else { '.' }
	return if starts { '${dot}startsWith' } else { '${dot}endsWith' }
}

// pssew_property_start ports the start of getPropertyRange: the first token after the object of
// the member that is not a `)`.
fn (mut c Checker) pssew_property_start(member C.TSNode) ?int {
	object := unwrap_parens(node_field(member, 'object')?)
	tokens := c.source_tokens(member)
	mut offset := node_end(object)
	for {
		token := tokens.after(offset, false)?
		if !c.token_is(token, ')') {
			return token.start
		}
		offset = token.end
	}
	return none
}

// pssew_fix_with_right ports fixWithRightOperand: the right operand becomes the argument of the
// method. `foo.slice(0, 3) === 'bar'` → `foo.startsWith('bar')`.
fn (mut c Checker) pssew_fix_with_right(binary C.TSNode, starts bool, optional bool) []Fix {
	// getLeftNode: the left side, or its callee if it is a call, must be a member.
	mut left := unwrap_parens(node_field(binary, 'left') or { return []Fix{} })
	if _ := call_arguments(left) {
		left = unwrap_parens(node_field(left, 'function') or { return []Fix{} })
	}
	if !is_member(left) {
		return []Fix{}
	}
	property_start := c.pssew_property_start(left) or { return []Fix{} }
	right := unwrap_parens(node_field(binary, 'right') or { return []Fix{} })
	mut fixes := []Fix{}
	if operator_of(binary).starts_with('!') {
		fixes << fix_insert_before(binary, '!')
	}
	fixes << fix_replace_range(property_start, node_start(right), pssew_method(starts, optional) +
		'(')
	fixes << fix_replace_range(node_end(right), node_end(binary), ')')
	return fixes
}

// pssew_fix_with_argument ports fixWithArgument: the first argument stays as the search string.
// `foo.indexOf('bar') === 0` → `foo.startsWith('bar')`.
fn (mut c Checker) pssew_fix_with_argument(binary C.TSNode, call C.TSNode, callee C.TSNode, starts bool) []Fix {
	property_start := c.pssew_property_start(callee) or { return []Fix{} }
	mut fixes := []Fix{}
	if operator_of(binary).starts_with('!') {
		fixes << fix_insert_before(binary, '!')
	}
	fixes << fix_replace_range(property_start, node_end(callee), pssew_method(starts, is_optional_element(callee)))
	fixes << fix_remove_range(node_end(call), node_end(binary))
	return fixes
}

// pssew_test handles `/^bar/.test(foo)`, reported at the call; no type check.
fn (mut c Checker) pssew_test(call C.TSNode, mut out []PssewCandidate) {
	args := call_arguments(call) or { return }
	callee := unwrap_parens(node_field(call, 'function') or { return })
	if node_kind(callee) != 'member_expression' || is_estree_chain_root(callee) {
		return
	}
	property := node_field(callee, 'property') or { return }
	if node_kind(property) != 'property_identifier' || c.identifier_name(property) != 'test'
		|| args.len != 1 {
		return
	}
	parsed := c.pssew_parse_regexp(node_field(callee, 'object') or { return }) or { return }
	// The fixer: only the argument stays (in parentheses unless it is a Literal, a TemplateLiteral,
	// an Identifier, a MemberExpression or a CallExpression), followed by the method and the text;
	// the `)` of the call closes it.
	argument := unwrap_parens(args[0])
	needs_paren := pinc_needs_paren(argument)
	mut fixes := [fix_remove_range(node_start(call), node_start(argument))]
	if needs_paren {
		fixes << fix_insert_before(argument, '(')
	}
	method := pssew_method(parsed.starts, is_optional_element(callee))
	fixes << fix_insert_after(argument, '${if needs_paren { ')' } else { '' }}${method}(${parsed.text}')
	out << PssewCandidate{
		report:     position_of(call)
		message_id: pssew_message(parsed.starts)
		object:     call
		typed:      false
		fixes:      fixes
	}
}

// pssew_is_number ports isNumber: the static value is that number.
fn (mut c Checker) pssew_is_number(n C.TSNode, value f64) bool {
	v := c.get_static_value(n)
	return v.found && v.value.kind == .number_ && v.value.number == value
}

// pssew_is_last_index ports isLastIndexExpression: `foo.length - 1`.
fn (mut c Checker) pssew_is_last_index(n C.TSNode, expected C.TSNode) bool {
	node := unwrap_parens(n)
	return estree_binary_kind(node) == 'BinaryExpression' && operator_of(node) == '-'
		&& c.pssew_is_length(node_field(node, 'left') or { return false }, expected)
		&& c.pssew_is_number(node_field(node, 'right') or { return false }, 1)
}

// pssew_is_length ports isLengthExpression: `x.length` of the same tokens as `expected`, or a
// static number equal to the length of `expected`'s static string.
fn (mut c Checker) pssew_is_length(n C.TSNode, expected C.TSNode) bool {
	node := unwrap_parens(n)
	if is_member(node) && !is_estree_chain_root(node) {
		name := c.property_name(node) or { return false }
		object := node_field(node, 'object') or { return false }
		return name == 'length' && c.pssew_tokens(object) == c.pssew_tokens(expected)
	}
	length := c.get_static_value(node)
	text := c.get_static_value(expected)
	return length.found && text.found && length.value.kind == .number_
		&& text.value.kind == .string_ && length.value.number == text.value.units.len
}

// pssew_is_length_ahead_of_end ports isLengthAheadOfEnd: `-substring.length` or
// `parentString.length - substring.length`.
fn (mut c Checker) pssew_is_length_ahead_of_end(n C.TSNode, substring C.TSNode, parent_string C.TSNode) bool {
	node := unwrap_parens(n)
	if node_kind(node) == 'unary_expression' && operator_of(node) == '-' {
		return c.pssew_is_length(node_field(node, 'argument') or { return false }, substring)
	}
	return estree_binary_kind(node) == 'BinaryExpression' && operator_of(node) == '-'
		&& c.pssew_is_length(node_field(node, 'left') or { return false }, parent_string)
		&& c.pssew_is_length(node_field(node, 'right') or { return false }, substring)
}

// pssew_tokens are the tokens of a node as ESLint's tokenizer gives them (their texts):
// literals are single tokens, a template splits at its substitutions, comments are skipped.
fn (c &Checker) pssew_tokens(n C.TSNode) []string {
	mut out := []string{}
	c.pssew_collect_tokens(unwrap_parens(n), mut out, 0)
	return out
}

fn (c &Checker) pssew_collect_tokens(n C.TSNode, mut out []string, depth int) {
	if depth > max_expression_depth {
		return
	}
	kind := node_kind(n)
	if kind == 'comment' {
		return
	}
	if kind in ['string', 'number', 'regex'] || C.ts_node_child_count(n) == 0 {
		if node_end(n) > node_start(n) {
			out << c.text(n)
		}
		return
	}
	if kind == 'template_string' {
		mut start := node_start(n)
		for child in named_children(n) {
			if node_kind(child) != 'template_substitution' {
				continue
			}
			out << c.src[start..node_start(child) + 2]
			if inner := first_named(child) {
				c.pssew_collect_tokens(inner, mut out, depth + 1)
			}
			start = node_end(child) - 1
		}
		out << c.src[start..node_end(n)]
		return
	}
	for child in children(n) {
		c.pssew_collect_tokens(child, mut out, depth + 1)
	}
}

// pssew_parse_regexp ports parseRegExp: for a static RegExp starting with `^` or (exclusively)
// ending with `$`, without `i` nor `m`, whose other elements are characters, whether it is the
// startsWith form.
fn (mut c Checker) pssew_parse_regexp(n C.TSNode) ?PssewRegexp {
	value := c.get_static_value(n)
	if !value.found || value.value.kind != .regexp_ {
		return none
	}
	re := value.value.regexp
	source := re.source
	starts := source.len > 0 && source[0] == `^`
	ends := source.len > 0 && source.last() == `$`
	if starts == ends || re.flags.contains('i') || re.flags.contains('m') {
		return none
	}
	mode := if re.flags.contains('u') { RegexpMode.unicode } else { RegexpMode.annex_b }
	pattern := regexp_parse(source, mode)
	if !pattern.valid || pattern.alternatives.len != 1 {
		return none
	}
	mut elements := pattern.alternatives[0].clone()
	if elements.len > 0 && elements[0].kind == .assertion_start {
		elements.delete(0)
	} else if elements.len > 0 {
		elements.delete_last()
	}
	if elements.any(it.kind != .character) {
		return none
	}
	// String.fromCodePoint of the characters, as UTF-16 units.
	mut units := []u16{}
	for element in elements {
		if element.value > 0xffff {
			v := element.value - 0x10000
			units << u16(0xd800 + (v >> 10))
			units << u16(0xdc00 + (v & 0x3ff))
		} else {
			units << u16(element.value)
		}
	}
	return PssewRegexp{
		starts: starts
		text:   pssew_json_string(units)
	}
}

// pssew_json_string ports JSON.stringify of a string, given as its UTF-16 units: quotes,
// backslashes and control characters are escaped, and so is a lone surrogate.
fn pssew_json_string(units []u16) string {
	mut out := ['"']
	mut i := 0
	for i < units.len {
		u := units[i]
		if u >= 0xd800 && u <= 0xdbff && i + 1 < units.len && units[i + 1] >= 0xdc00
			&& units[i + 1] <= 0xdfff {
			out << stv_units_string(units[i..i + 2])
			i += 2
			continue
		}
		out << match u {
			`"` { '\\"' }
			`\\` { '\\\\' }
			8 { '\\b' }
			9 { '\\t' }
			10 { '\\n' }
			12 { '\\f' }
			13 { '\\r' }
			else {
				if u < 0x20 || (u >= 0xd800 && u <= 0xdfff) {
					'\\u${u:04x}'
				} else {
					stv_units_string([u])
				}
			}
		}
		i++
	}
	out << '"'
	return out.join('')
}
