module rules

import estree
import regexpp
import treesitter { Ident }

// The shared code of the `regexp/*` rules, ported from lib/utils of eslint-plugin-regexp 3.3.3:
// createRule and defineRegexpVisitor of utils/index.ts (where the regular expressions of a file come
// from: the regular expression literals, and the patterns and flags of `RegExp(…)` and
// `new RegExp(…)` calls of the global RegExp, through ReferenceTracker), PatternSource of
// ast-utils/pattern-source.ts (where each part of a pattern is in the source), parseFlags of
// regex-syntax.ts, the fixes of utils/index.ts (fixReplaceNode, fixReplaceQuant, fixReplaceFlags)
// and the location helpers of ast-utils/regex.ts. The other parts are in regexp_utils_*.v.
//
// ESLint runs every regexp rule of a file on one shared visitor (defineRegexpVisitor keeps the
// rules of a Program in a WeakMap): the calls of the global RegExp are verified when the Program is
// entered, then each regular expression literal no call owns, in the order of the traversal. veslint
// lists them once per file in that order (rx_regexps) and each rule walks their patterns.
//
// Patterns are UTF-16 units, as in JavaScript: the offsets of regexpp's nodes and of the ranges of
// a pattern (PatternRange) are units of the pattern; the ranges in the source are bytes.

// RxFlags are the flags of a regular expression (parseFlags: the non-standard ones are left out).
struct RxFlags {
	dot_all      bool
	global       bool
	has_indices  bool
	ignore_case  bool
	multiline    bool
	sticky       bool
	unicode      bool
	unicode_sets bool
}

// rx_parse_flags ports parseFlags.
fn rx_parse_flags(flags string) RxFlags {
	return RxFlags{
		dot_all:      flags.contains('s')
		global:       flags.contains('g')
		has_indices:  flags.contains('d')
		ignore_case:  flags.contains('i')
		multiline:    flags.contains('m')
		sticky:       flags.contains('y')
		unicode:      flags.contains('u')
		unicode_sets: flags.contains('v')
	}
}

// RxRange is a PatternRange: [start, end) in units of the pattern.
struct RxRange {
	start int
	end   int
}

// RxSegment is a PatternSegment: a part of the pattern given by one expression, [start, end) in
// units of the whole pattern.
struct RxSegment {
	node  int
	value []u16
	start int
	end   int
}

// RxReplaceKind is the `type` of a PatternReplaceRange.
enum RxReplaceKind {
	regexp
	single_quoted
	double_quoted
}

// RxReplaceRange is a PatternReplaceRange: a range of the source (bytes) that can be edited, and
// how a text written there is escaped.
struct RxReplaceRange {
	start int
	end   int
	kind  RxReplaceKind
}

// RxPatternSource is a PatternSource: the expression of the pattern, its value and its segments,
// and, when the pattern comes from a RegExp object, its `regexpValue` (`ownedNode` is the
// regular expression literal it owns, -1 for none).
struct RxPatternSource {
	node             int
	value            []u16
	segments         []RxSegment
	has_regexp_value bool
	regexp_source    []u16
	regexp_flags     string
	owned_node       int = -1
}

// RxKind tells which visitor of a rule gets a regular expression: a parsed literal
// (createLiteralVisitor), a parsed pattern of a RegExp call (createSourceVisitor), a pattern that
// does not parse (visitInvalid) or one whose value is not known (visitUnknown).
enum RxKind {
	literal
	source
	invalid
	unknown
}

// RxRegExp is the RegExpContext of a regular expression (or the UnparsableRegExpContext):
// `node` is the expression of the pattern (the literal itself for a literal), `regexp_node` the
// literal or the call, `flags_node` the expression of the flags (-1 for none), `flags_string` the
// value of the flags (has_flags_string false: null).
struct RxRegExp {
	kind             RxKind
	node             int
	regexp_node      int
	flags_node       int = -1
	flags_string     string
	has_flags_string bool
	owns_flags       bool
	flags            RxFlags
	// The PatternSource (has_source false for an unknown pattern).
	source     RxPatternSource
	has_source bool
	// The pattern, parsed (literal and source), and the error of one that does not parse.
	ast   regexpp.Ast
	error regexpp.SyntaxError
}

// visited tells whether a rule's visitor gets the regular expression: regexpp's parser rejected it
// with something else than a SyntaxError (node -1), which no visitor gets.
fn (re &RxRegExp) visited() bool {
	return re.node >= 0
}

// RxFile is what veslint keeps of the regular expressions of a file (see rx_regexps).
struct RxFile {
mut:
	built   bool
	regexps []RxRegExp
}

// rx_regexps are the regular expressions of the file, in the order the shared visitor of
// defineRegexpVisitor verifies them; none when the file has no ESTree.
fn (mut c Checker) rx_regexps(root C.TSNode, abs_path string) []RxRegExp {
	if c.rx_file.built {
		return c.rx_file.regexps
	}
	c.rx_file.built = true
	t := c.es_tree(root, abs_path) or { return [] }
	mut out := []RxRegExp{}
	// Program: the calls of RegExp (`new RegExp()`, `RegExp()`, `new window.RegExp()`,
	// `const {RegExp: a} = window; new a()`…), the literals of their patterns left to them.
	mut owned := map[int]bool{}
	trace := {
		'RegExp': EsTrace{
			call:      true
			construct: true
		}
	}
	mut calls := []RxCallData{}
	for traced in c.es_global_references(root, trace) {
		call := c.es_index_of(t, traced.node) or { continue }
		if t.typ(call) !in [.call_expression, .new_expression] {
			continue
		}
		args := t.list(call, .arguments) or { []int{} }
		if args.len == 0 || t.typ(args[0]) == .spread_element {
			continue
		}
		pattern_arg := args[0]
		source := c.rx_pattern_source_from_expression(root, t, pattern_arg)
		if s := source {
			for n in rx_owned_regexp_literals(t, s) {
				owned[n] = true
			}
		}
		mut flags_node := -1
		mut flags_string := ''
		mut has_flags_string := false
		mut owns_flags := false
		if args.len > 1 {
			if t.typ(args[1]) != .spread_element {
				flags_node = c.rx_dereference_owned_variable(root, t, args[1])
				if value := c.rx_string_if_constant(root, t, flags_node) {
					flags_string = value
					has_flags_string = true
				}
				owns_flags = rx_is_string_literal(t, flags_node)
			}
		} else if s := source {
			if s.has_regexp_value {
				flags_string = s.regexp_flags
				has_flags_string = true
				owns_flags = s.owned_node >= 0
				flags_node = s.owned_node
			} else {
				has_flags_string = true
				owns_flags = true
			}
		} else {
			has_flags_string = true
			owns_flags = true
		}
		calls << RxCallData{
			call:             call
			pattern_node:     pattern_arg
			source:           source
			flags_node:       flags_node
			flags_string:     flags_string
			has_flags_string: has_flags_string
			owns_flags:       owns_flags
		}
	}
	for data in calls {
		out << rx_verify(data.pattern_node, data.flags_node, data.call, data.source, data.flags_string,
			data.has_flags_string, data.owns_flags, .source)
	}
	// Literal: each regular expression literal that no call owns, in the order of the traversal.
	for step in t.steps() {
		if step.leave || !rx_is_regexp_literal(t, step.node) || step.node in owned {
			continue
		}
		regex := t.prop(step.node, .regex) or { continue }
		source := rx_pattern_source_from_literal(t, step.node)
		out << rx_verify(step.node, step.node, step.node, source, regex.str2, true, true, .literal)
	}
	c.rx_file.regexps = out
	return out
}

struct RxCallData {
	call             int
	pattern_node     int
	source           ?RxPatternSource
	flags_node       int
	flags_string     string
	has_flags_string bool
	owns_flags       bool
}

// rx_verify ports `verify` of buildRegexpVisitor: the pattern parsed with regexpp (ecmaVersion
// 2025, not strict) and the flags given.
fn rx_verify(pattern_node int, flags_node int, regexp_node int, source ?RxPatternSource, flags_string string, has_flags_string bool, owns_flags bool, kind RxKind) RxRegExp {
	flags := rx_parse_flags(flags_string)
	s := source or {
		return RxRegExp{
			kind:             .unknown
			node:             pattern_node
			regexp_node:      regexp_node
			flags_node:       flags_node
			flags_string:     flags_string
			has_flags_string: has_flags_string
			owns_flags:       owns_flags
			flags:            flags
		}
	}
	ast := regexpp.parse_pattern(s.value, 0, s.value.len, regexpp.PatternFlags{
		unicode:      flags.unicode
		unicode_sets: flags.unicode_sets
	}, regexpp.Options{}) or {
		if err is regexpp.SyntaxError {
			return RxRegExp{
				kind:             .invalid
				node:             pattern_node
				regexp_node:      regexp_node
				flags_node:       flags_node
				flags_string:     flags_string
				has_flags_string: has_flags_string
				owns_flags:       owns_flags
				flags:            flags
				source:           s
				has_source:       true
				error:            err
			}
		}
		// regexpp's parser threw something else: the regular expression is left alone.
		return RxRegExp{
			kind:        .unknown
			node:        -1
			regexp_node: regexp_node
		}
	}
	return RxRegExp{
		kind:             kind
		node:             pattern_node
		regexp_node:      regexp_node
		flags_node:       flags_node
		flags_string:     flags_string
		has_flags_string: has_flags_string
		owns_flags:       owns_flags
		flags:            flags
		source:           s
		has_source:       true
		ast:              ast
	}
}

// rx_is_regexp_literal ports isRegexpLiteral.
fn rx_is_regexp_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && t.prop(node, .regex) != none
}

// rx_is_string_literal ports isStringLiteral.
fn rx_is_string_literal(t &estree.EsTree, node int) bool {
	return node >= 0 && t.typ(node) == .literal && t.get(node, .value) is string
}

// rx_string_value is the value of a string literal as UTF-16 units.
fn rx_string_value(t &estree.EsTree, node int) []u16 {
	v := t.get(node, .value)
	if v is string {
		return regexpp.to_utf16(v)
	}
	return []
}

// rx_bytes_after_units is the byte offset `units` UTF-16 units after the byte offset `from` of
// the source.
fn rx_bytes_after_units(src string, from int, units int) int {
	mut i := from
	mut u := 0
	for u < units && i < src.len {
		b := src[i]
		size := if b < 0x80 {
			1
		} else if b >= 0xf0 {
			4
		} else if b >= 0xe0 {
			3
		} else {
			2
		}
		i += size
		u += if size == 4 { 2 } else { 1 }
	}
	return if i > src.len { src.len } else { i }
}

// rx_pattern_source_from_literal ports PatternSource.fromRegExpLiteral.
fn rx_pattern_source_from_literal(t &estree.EsTree, node int) RxPatternSource {
	regex := t.prop(node, .regex) or { return RxPatternSource{} }
	value := regexpp.to_utf16(regex.str)
	return RxPatternSource{
		node:             node
		value:            value
		segments:         [RxSegment{
			node:  node
			value: value
			start: 0
			end:   value.len
		}]
		has_regexp_value: true
		regexp_source:    value
		regexp_flags:     regex.str2
		owned_node:       node
	}
}

// rx_pattern_source_from_expression ports PatternSource.fromExpression: none when the value of
// the pattern is not known.
fn (mut c Checker) rx_pattern_source_from_expression(root C.TSNode, t &estree.EsTree, expression int) ?RxPatternSource {
	e := c.rx_dereference_owned_variable(root, t, expression)
	if rx_is_regexp_literal(t, e) {
		return rx_pattern_source_from_literal(t, e)
	}
	flat := c.rx_flatten_plus(root, t, e)
	mut items := []RxSegment{}
	mut value := []u16{}
	for part in flat {
		if t.typ(part) == .private_identifier {
			return none
		}
		static_value := c.rx_static_value(root, t, part)
		if !static_value.found {
			return none
		}
		if flat.len == 1 && static_value.value.kind == .regexp_ {
			// A reference to something that is a RegExp object, not owned.
			source := static_value.value.regexp.source
			return RxPatternSource{
				node:             part
				value:            source
				segments:         [RxSegment{
					node:  part
					value: source
					start: 0
					end:   source.len
				}]
				has_regexp_value: true
				regexp_source:    source
				regexp_flags:     static_value.value.regexp.flags
			}
		}
		if static_value.value.kind != .string_ {
			return none
		}
		items << RxSegment{
			node:  part
			value: static_value.value.units
			start: value.len
			end:   value.len + static_value.value.units.len
		}
		value << static_value.value.units
	}
	return RxPatternSource{
		node:     e
		value:    value
		segments: items
	}
}

// rx_flatten_plus ports flattenPlus: the operands of `+`, owned constants dereferenced.
fn (mut c Checker) rx_flatten_plus(root C.TSNode, t &estree.EsTree, e int) []int {
	if t.typ(e) == .binary_expression && (t.string_of(e, .operator) or { '' }) == '+' {
		left := t.node(e, .left) or { return [e] }
		right := t.node(e, .right) or { return [e] }
		mut out := if t.typ(left) != .private_identifier {
			c.rx_flatten_plus(root, t, left)
		} else {
			[left]
		}
		out << c.rx_flatten_plus(root, t, right)
		return out
	}
	de_ref := c.rx_dereference_owned_variable(root, t, e)
	if de_ref != e {
		return c.rx_flatten_plus(root, t, de_ref)
	}
	return [e]
}

// rx_segment_owned_literal ports PatternSegment#getOwnedRegExpLiteral: the literal itself, or the
// literal of `/foo/.source`; -1 for none.
fn rx_segment_owned_literal(t &estree.EsTree, segment RxSegment) int {
	node := segment.node
	if rx_is_regexp_literal(t, node) {
		return node
	}
	if t.typ(node) == .member_expression {
		object := t.node(node, .object) or { return -1 }
		if t.typ(object) != .super && rx_is_regexp_literal(t, object)
			&& (rx_property_name_unscoped(t, node) or { '' }) == 'source' {
			return object
		}
	}
	return -1
}

// rx_owned_regexp_literals ports PatternSource#getOwnedRegExpLiterals.
fn rx_owned_regexp_literals(t &estree.EsTree, source RxPatternSource) []int {
	mut out := []int{}
	for segment in source.segments {
		owned := rx_segment_owned_literal(t, segment)
		if owned >= 0 {
			out << owned
		}
	}
	return out
}

// rx_replace_range_from_literal ports PatternReplaceRange.fromLiteral.
fn (c &Checker) rx_replace_range_from_literal(t &estree.EsTree, node int, node_range RxRange, range RxRange) ?RxReplaceRange {
	start := range.start - node_range.start
	end := range.end - node_range.start
	if rx_is_regexp_literal(t, node) {
		node_start := t.nodes[node].start + 1
		return RxReplaceRange{
			start: rx_bytes_after_units(c.src, node_start, start)
			end:   rx_bytes_after_units(c.src, node_start, end)
			kind:  .regexp
		}
	}
	if rx_is_string_literal(t, node) {
		s, e := c.rx_string_value_range(t, node, start, end)?
		return RxReplaceRange{
			start: s
			end:   e
			kind:  if c.src[t.nodes[node].start] == `'` { .single_quoted } else { .double_quoted }
		}
	}
	return none
}

// rx_segment_replace_range ports PatternSegment#getReplaceRange.
fn (c &Checker) rx_segment_replace_range(t &estree.EsTree, segment RxSegment, range RxRange) ?RxReplaceRange {
	if !(segment.start <= range.start && range.end <= segment.end) {
		return none
	}
	node_range := RxRange{segment.start, segment.end}
	regexp := rx_segment_owned_literal(t, segment)
	if regexp >= 0 {
		return c.rx_replace_range_from_literal(t, regexp, node_range, range)
	}
	if t.typ(segment.node) == .literal {
		return c.rx_replace_range_from_literal(t, segment.node, node_range, range)
	}
	return none
}

// rx_segments_of ports PatternSource#getSegments: the segments the range overlaps.
fn rx_segments_of(source &RxPatternSource, range RxRange) []RxSegment {
	return source.segments.filter(it.start < range.end && range.start < it.end)
}

// rx_replace_range ports PatternSource#getReplaceRange.
fn (c &Checker) rx_replace_range(t &estree.EsTree, source &RxPatternSource, range RxRange) ?RxReplaceRange {
	segments := rx_segments_of(source, range)
	if segments.len == 1 {
		return c.rx_segment_replace_range(t, segments[0], range)
	}
	return none
}

// rx_ast_range ports PatternSource#getAstRange: the source range (bytes) of a range of the pattern.
fn (c &Checker) rx_ast_range(t &estree.EsTree, source &RxPatternSource, range RxRange) (int, int) {
	overlapping := rx_segments_of(source, range)
	if overlapping.len == 1 {
		if replace := c.rx_segment_replace_range(t, overlapping[0], range) {
			return replace.start, replace.end
		}
		node := overlapping[0].node
		return t.nodes[node].start, t.nodes[node].end
	}
	if overlapping.len == 0 {
		return t.nodes[source.node].start, t.nodes[source.node].end
	}
	mut min := t.nodes[overlapping[0].node].start
	mut max := t.nodes[overlapping[0].node].end
	for item in overlapping {
		if t.nodes[item.node].start < min {
			min = t.nodes[item.node].start
		}
		if t.nodes[item.node].end > max {
			max = t.nodes[item.node].end
		}
	}
	return min, max
}

// rx_location ports getRegexpLocation (PatternSource#getAstLocation): a place of the source from
// its offsets (sourceCode.getLocFromIndex).
fn (c &Checker) rx_location(t &estree.EsTree, re &RxRegExp, range RxRange) Ident {
	start, end := c.rx_ast_range(t, &re.source, range)
	return c.position_range(start, end)
}

// rx_report is a report at a range of a pattern (getRegexpLocation: a `loc` from offsets).
fn (c &Checker) rx_report(t &estree.EsTree, re &RxRegExp, range RxRange, message_id string, data map[string]string) Finding {
	return Finding{
		stmt:       c.rx_location(t, re, range)
		message_id: message_id
		data:       data
		text_loc:   true
	}
}

// rx_node_range is the PatternRange of a node of the pattern.
fn rx_node_range(ast &regexpp.Ast, i int) RxRange {
	return RxRange{ast.nodes[i].start, ast.nodes[i].end}
}

// rx_escape ports PatternReplaceRange#escape.
fn rx_escape(kind RxReplaceKind, text string) string {
	if kind in [.double_quoted, .single_quoted] {
		base := text.replace('\\', '\\\\').replace('\n', '\\n').replace('\r', '\\r').replace('\t',
			'\\t')
		if kind == .double_quoted {
			return base.replace('"', '\\"')
		}
		return base.replace("'", "\\'")
	}
	return text.replace('\n', '\\n').replace('\r', '\\r')
}

// rx_replace_fix ports PatternReplaceRange#replace.
fn rx_replace_fix(range RxReplaceRange, text string) Fix {
	return fix_replace_range(range.start, range.end, rx_escape(range.kind, text))
}

// rx_fix_replace_node ports fixReplaceNode with a text: none when the node cannot be edited (the
// fix is null).
fn (c &Checker) rx_fix_replace_node(t &estree.EsTree, re &RxRegExp, range RxRange, text string) ?Fix {
	replace := c.rx_replace_range(t, &re.source, range)?
	return rx_replace_fix(replace, text)
}

// rx_with_fix is the report with the fix, when there is one.
fn rx_with_fix(f Finding, fix ?Fix) Finding {
	x := fix or { return f }
	return Finding{
		...f
		has_fix: true
		fix:     x
	}
}

// rx_suggestion is a suggestion with the fix, none when the fix is null (ESLint leaves such a
// suggestion out).
fn rx_suggestion(message_id string, data map[string]string, fix ?Fix) ?Suggestion {
	x := fix?
	return Suggestion{
		message_id: message_id
		data:       data
		fix:        x
	}
}

// rx_quantifier_offsets ports getQuantifierOffsets: the quantifier without its element, its lazy
// `?` left out.
fn rx_quantifier_offsets(ast &regexpp.Ast, q int) (int, int) {
	n := ast.nodes[q]
	start := ast.nodes[n.element].end - n.start
	end := (n.end - n.start) - if n.greedy { 0 } else { 1 }
	return start, end
}

// RxQuant is a Quant: `greedy` is set when has_greedy (undefined otherwise).
struct RxQuant {
	min        f64
	max        f64
	greedy     bool
	has_greedy bool
}

// rx_quant_to_string ports quantToString (an invalid quantifier throws: none).
fn rx_quant_to_string(q RxQuant) ?string {
	infinite := regexpp.quantifier_is_infinite(q.max)
	if q.max < q.min || q.min < 0 || q.min != f64(i64(q.min))
		|| !(infinite || q.max == f64(i64(q.max))) {
		return none
	}
	min := i64(q.min)
	value := if q.min == 0 && q.max == 1 {
		'?'
	} else if q.min == 0 && infinite {
		'*'
	} else if q.min == 1 && infinite {
		'+'
	} else if q.min == q.max {
		'{${min}}'
	} else if infinite {
		'{${min},}'
	} else {
		'{${min},${i64(q.max)}}'
	}
	if q.has_greedy && !q.greedy {
		return '${value}?'
	}
	return value
}

// rx_fix_replace_quant ports fixReplaceQuant with a text, or with a Quant (`quant`): the
// quantifier (but not its element) replaced; with a Quant of another greediness, its `?` too.
fn (c &Checker) rx_fix_replace_quant(t &estree.EsTree, re &RxRegExp, q int, text string, quant ?RxQuant) ?Fix {
	o0, mut o1 := rx_quantifier_offsets(&re.ast, q)
	mut replacement := text
	if qt := quant {
		if qt.has_greedy && qt.greedy != re.ast.nodes[q].greedy {
			o1++
		}
		replacement = rx_quant_to_string(qt)?
	}
	start := re.ast.nodes[q].start
	replace := c.rx_replace_range(t, &re.source, RxRange{start + o0, start + o1})?
	return rx_replace_fix(replace, replacement)
}

// rx_fix_replace_flags ports fixReplaceFlags: the flags replaced and, with include_pattern, the
// whole pattern written again (so that the fixes of the pattern conflict with it); none when
// fixReplaceFlags gives null.
fn (c &Checker) rx_fix_replace_flags(t &estree.EsTree, re &RxRegExp, new_flags string, include_pattern bool) ?Fix {
	if !new_flags.bytes().all(it.is_letter()) {
		return none
	}
	regexp_node := re.regexp_node
	if include_pattern && rx_is_regexp_literal(t, regexp_node) {
		regex := t.prop(regexp_node, .regex)?
		return fix_replace_range(t.nodes[regexp_node].start, t.nodes[regexp_node].end, '/${regex.str}/${new_flags}')
	}
	mut flags_fix := Fix{}
	if rx_is_regexp_literal(t, regexp_node) {
		s, e := rx_flags_range(t, regexp_node)?
		flags_fix = fix_replace_range(s, e, new_flags)
	} else if re.flags_node >= 0 {
		s, e := rx_flags_range(t, re.flags_node)?
		flags_fix = fix_replace_range(s, e, new_flags)
	} else {
		// A RegExp call without a flags argument gets one.
		args := t.list(regexp_node, .arguments) or { []int{} }
		if args.len != 1 {
			return none
		}
		end := t.nodes[regexp_node].end
		flags_fix = fix_replace_range(end - 1, end, ', "${new_flags}")')
	}
	if !include_pattern {
		return flags_fix
	}
	if !re.has_source {
		return none
	}
	pattern_range := c.rx_replace_range(t, &re.source, RxRange{0, re.source.value.len})?
	pattern_fix := rx_replace_fix(pattern_range, regexpp.utf16_to_wtf8(re.source.value))
	_, merged := c.merge_fixes([pattern_fix, flags_fix]) or { return none }
	return merged
}

// rx_flags_range ports getFlagsRange: the flags of a regular expression literal or the value of a
// string literal; none for any other expression.
fn rx_flags_range(t &estree.EsTree, flags_node int) ?(int, int) {
	if flags_node < 0 {
		return none
	}
	if rx_is_regexp_literal(t, flags_node) {
		regex := t.prop(flags_node, .regex)?
		end := t.nodes[flags_node].end
		return end - regex.str2.len, end
	}
	if rx_is_string_literal(t, flags_node) {
		return t.nodes[flags_node].start + 1, t.nodes[flags_node].end - 1
	}
	return none
}

// rx_flags_report is a report at getFlagsLocation: the flags, the character before them when there
// are none (a `loc` from offsets), or else the flags expression or the regular expression (its
// `loc`).
fn (c &Checker) rx_flags_report(t &estree.EsTree, regexp_node int, flags_node int, message_id string, data map[string]string) Finding {
	mut start, end := rx_flags_range(t, flags_node) or {
		node := if flags_node >= 0 { flags_node } else { regexp_node }
		return Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: message_id
			data:       data
		}
	}
	if start == end {
		start = c.rx_byte_before(start)
	}
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       data
		text_loc:   true
	}
}

// rx_byte_before is the byte offset of the UTF-16 unit before the byte `offset` (`range[0]--`):
// the character before it.
fn (c &Checker) rx_byte_before(offset int) int {
	mut i := offset - 1
	for i > 0 && (c.src[i] & 0xc0) == 0x80 {
		i--
	}
	return if i < 0 { 0 } else { i }
}

// rx_flag_range ports getFlagRange: the place of a flag in the flags node.
fn (c &Checker) rx_flag_range(t &estree.EsTree, flags_node int, flag string) ?(int, int) {
	if flags_node < 0 || flag == '' {
		return none
	}
	if rx_is_regexp_literal(t, flags_node) {
		regex := t.prop(flags_node, .regex)?
		index := regex.str2.index(flag) or { return none }
		start := t.nodes[flags_node].end - regex.str2.len + index
		return start, start + 1
	}
	if rx_is_string_literal(t, flags_node) {
		value := rx_string_value(t, flags_node)
		index := rx_units_index(value, regexpp.to_utf16(flag)) or { return none }
		return c.rx_string_value_range(t, flags_node, index, index + 1)
	}
	return none
}

// rx_flag_report is a report at getFlagLocation.
fn (c &Checker) rx_flag_report(t &estree.EsTree, regexp_node int, flags_node int, flag string, message_id string, data map[string]string) Finding {
	start, end := c.rx_flag_range(t, flags_node, flag) or {
		node := if flags_node >= 0 { flags_node } else { regexp_node }
		return Finding{
			stmt:       c.es_tree_position(t, node)
			message_id: message_id
			data:       data
		}
	}
	return Finding{
		stmt:       c.position_range(start, end)
		message_id: message_id
		data:       data
		text_loc:   true
	}
}

// rx_units_index is String#indexOf on UTF-16 units.
fn rx_units_index(haystack []u16, needle []u16) ?int {
	if needle.len == 0 {
		return 0
	}
	for i := 0; i + needle.len <= haystack.len; i++ {
		if haystack[i..i + needle.len] == needle {
			return i
		}
	}
	return none
}
