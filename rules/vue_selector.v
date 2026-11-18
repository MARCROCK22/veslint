module rules

import jsregexp

// lib/utils/selector.ts of eslint-plugin-vue 10.12.1 (prefix `vsel_`): parseSelector, CSS
// selectors (as postcss-selector-parser reads them, and nth-check's An+B) that test V elements:
// type, universal, class, id and attribute selectors, the combinators ` `, `>`, `+` and `~`, and
// the pseudo-classes :not, :is, :where, :has, :empty, :nth-child, :nth-last-child, :first-child,
// :last-child, :only-child and their -of-type forms. The matchers are nodes of an arena, built
// the way selectorToVElementMatcher folds a selector.

enum VselKind {
	never // a selector that did not parse: matches nothing
	tag
	universal
	class_name
	id
	attribute
	compound    // a and b
	combination // `right` on the element and `left` on an element `comb` relates it to
	subject     // element === subject (the left of a relative selector of :has)
	any         // one of `list`
	not_        // none of `list`
	has         // one of the elements from the subject `list[i]` starts at matches it
	empty
	position         // nth (nth-check) of the element among its parent's elements
	position_of_type // the same among those of its name
}

struct VselMatcher {
mut:
	kind  VselKind
	value string // tag, class, id, attribute name
	// An attribute selector: its operator ('' to test presence), value and `i` flag.
	operator    string
	attr_value  string
	insensitive bool
	a           int = -1
	b           int = -1
	comb        string
	list        []int
	// :has: whether each selector of `list` starts from the elements after (`+`/`~`) or below.
	from_after []bool
	// position tests: nth-check's (a, b), counted from the end when `last`; `only` for
	// :only-child and :only-of-type.
	nth_a int
	nth_b int
	last  bool
	only  bool
}

// VselSelector is the result of parseSelector: the root matcher, or the error a report gives.
struct VselSelector {
	matchers []VselMatcher
	root     int = -1
	error    string
}

struct VselParser {
	src string
mut:
	pos      int
	matchers []VselMatcher
}

// VselNode is a node of postcss-selector-parser's selector: a combinator (`comb` set) or a
// simple selector / pseudo-class, already a matcher.
struct VselNode {
	comb    string
	matcher int = -1
	// For :has, whether the selector starts with `+` or `~`.
}

fn vsel_parse(selector string) VselSelector {
	mut p := VselParser{
		src: selector
	}
	root := p.selector_list(false) or {
		msg := err.msg()
		if msg.starts_with('!') {
			return VselSelector{
				error: msg[1..]
			}
		}
		return VselSelector{
			error: 'Cannot parse selector: ${selector}.'
		}
	}
	if p.pos < p.src.len {
		return VselSelector{
			error: 'Cannot parse selector: ${selector}.'
		}
	}
	return VselSelector{
		matchers: p.matchers
		root:     root
	}
}

fn (mut p VselParser) add(m VselMatcher) int {
	p.matchers << m
	return p.matchers.len - 1
}

fn (mut p VselParser) skip_comments() {
	for p.pos + 1 < p.src.len && p.src[p.pos] == `/` && p.src[p.pos + 1] == `*` {
		end := p.src.index_after('*/', p.pos + 2) or { p.src.len - 2 }
		p.pos = end + 2
	}
}

fn vsel_is_space(b u8) bool {
	return b == ` ` || b == `\t` || b == `\n` || b == `\r` || b == `\f`
}

fn vsel_is_ident_char(b u8) bool {
	return (b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`) || (b >= `0` && b <= `9`) || b == `-`
		|| b == `_` || b >= 0x80 || b == `\\`
}

fn (mut p VselParser) ident() !string {
	start := p.pos
	mut out := []u8{}
	for p.pos < p.src.len && vsel_is_ident_char(p.src[p.pos]) {
		if p.src[p.pos] == `\\` && p.pos + 1 < p.src.len {
			out << p.src[p.pos + 1]
			p.pos += 2
			continue
		}
		out << p.src[p.pos]
		p.pos++
	}
	if p.pos == start {
		return error('ident')
	}
	return out.bytestr()
}

// selector_list parses selectors separated by commas, up to the end or a `)` (`nested`), into
// a matcher of any of them; with `relative` (inside :has) a selector may start with a
// combinator.
fn (mut p VselParser) selector_list(nested bool) !int {
	mut list := []int{}
	for {
		nodes := p.selector_nodes()!
		list << p.selector_matcher(nodes)!
		if p.pos < p.src.len && p.src[p.pos] == `,` {
			p.pos++
			continue
		}
		break
	}
	if nested && (p.pos >= p.src.len || p.src[p.pos] != `)`) {
		return error('unclosed')
	}
	return p.add(VselMatcher{
		kind: .any
		list: list
	})
}

// selector_nodes reads one selector into its nodes (cleanSelectorChildren: no descendant
// combinator first, last, or next to another combinator).
fn (mut p VselParser) selector_nodes() ![]VselNode {
	mut nodes := []VselNode{}
	for p.pos < p.src.len {
		p.skip_comments()
		if p.pos >= p.src.len {
			break
		}
		b := p.src[p.pos]
		if b == `,` || b == `)` {
			break
		}
		if vsel_is_space(b) {
			for p.pos < p.src.len && vsel_is_space(p.src[p.pos]) {
				p.pos++
			}
			p.skip_comments()
			if p.vsel_at_combinator() {
				continue
			}
			if p.pos >= p.src.len || p.src[p.pos] in [`,`, `)`] {
				break
			}
			if nodes.len > 0 && nodes.last().comb == '' {
				nodes << VselNode{
					comb: ' '
				}
			}
			continue
		}
		if p.vsel_at_combinator() {
			// postcss-selector-parser reads a run of `+>~|` as one combinator token (`>>` is one).
			start := p.pos
			for p.pos < p.src.len && p.src[p.pos] in [`>`, `+`, `~`, `|`] {
				p.pos++
			}
			if nodes.len > 0 && nodes.last().comb == ' ' {
				nodes.pop()
			}
			nodes << VselNode{
				comb: p.src[start..p.pos]
			}
			for p.pos < p.src.len && vsel_is_space(p.src[p.pos]) {
				p.pos++
			}
			continue
		}
		nodes << VselNode{
			matcher: p.simple()!
		}
	}
	if nodes.len > 0 && nodes.last().comb == ' ' {
		nodes.pop()
	}
	return nodes
}

// vsel_at_combinator tells whether a combinator token starts here (a lone `|` is a namespace).
fn (p &VselParser) vsel_at_combinator() bool {
	if p.pos >= p.src.len {
		return false
	}
	b := p.src[p.pos]
	if b in [`>`, `+`, `~`] {
		return true
	}
	return b == `|` && p.pos + 1 < p.src.len && p.src[p.pos + 1] in [`>`, `+`, `~`, `|`]
}

// selector_matcher is selectorToVElementMatcher.
fn (mut p VselParser) selector_matcher(nodes []VselNode) !int {
	mut result := -1
	mut i := 0
	for i < nodes.len {
		node := nodes[i]
		if node.comb != '' {
			i++
			if i >= nodes.len {
				return error("!Expected selector after '${node.comb}'.")
			}
			if nodes[i].comb != '' {
				return error("!Unexpected combinator '${nodes[i].comb}'.")
			}
			if node.comb !in [' ', '>', '+', '~'] {
				return error('!Unknown combinator: ${node.comb}.')
			}
			left := if result >= 0 { result } else { p.add(VselMatcher{
					kind: .subject
				}) }
			result = p.add(VselMatcher{
				kind: .combination
				a:    left
				b:    nodes[i].matcher
				comb: node.comb
			})
		} else {
			result = if result >= 0 {
				p.add(VselMatcher{
					kind: .compound
					a:    result
					b:    node.matcher
				})
			} else {
				node.matcher
			}
		}
		i++
	}
	if result < 0 {
		return error('!Unexpected empty selector.')
	}
	return result
}

// simple reads a simple selector or a pseudo-class.
fn (mut p VselParser) simple() !int {
	b := p.src[p.pos]
	match b {
		`*` {
			p.pos++
			return p.add(VselMatcher{
				kind: .universal
			})
		}
		`.` {
			p.pos++
			return p.add(VselMatcher{
				kind:  .class_name
				value: p.ident()!
			})
		}
		`#` {
			p.pos++
			return p.add(VselMatcher{
				kind:  .id
				value: p.ident()!
			})
		}
		`[` {
			return p.attribute()
		}
		`:` {
			return p.pseudo()
		}
		`&` {
			return error('!Unsupported nesting selector.')
		}
		else {
			return p.add(VselMatcher{
				kind:  .tag
				value: p.ident()!
			})
		}
	}
}

fn (mut p VselParser) skip_spaces() {
	for p.pos < p.src.len && vsel_is_space(p.src[p.pos]) {
		p.pos++
	}
}

fn (mut p VselParser) attribute() !int {
	p.pos++
	p.skip_spaces()
	name := p.ident()!
	p.skip_spaces()
	if p.pos >= p.src.len {
		return error('attribute')
	}
	if p.src[p.pos] == `]` {
		p.pos++
		return p.add(VselMatcher{
			kind:  .attribute
			value: name
		})
	}
	mut operator := ''
	if p.src[p.pos] == `=` {
		operator = '='
		p.pos++
	} else if p.pos + 1 < p.src.len && p.src[p.pos + 1] == `=`
		&& p.src[p.pos] in [`~`, `|`, `^`, `$`, `*`] {
		operator = p.src[p.pos..p.pos + 2]
		p.pos += 2
	} else {
		return error('operator')
	}
	p.skip_spaces()
	mut value := ''
	if p.pos < p.src.len && (p.src[p.pos] == `"` || p.src[p.pos] == `'`) {
		quote := p.src[p.pos]
		p.pos++
		mut out := []u8{}
		for p.pos < p.src.len && p.src[p.pos] != quote {
			if p.src[p.pos] == `\\` && p.pos + 1 < p.src.len {
				p.pos++
			}
			out << p.src[p.pos]
			p.pos++
		}
		if p.pos >= p.src.len {
			return error('quote')
		}
		p.pos++
		value = out.bytestr()
	} else {
		value = p.ident()!
	}
	p.skip_spaces()
	mut insensitive := false
	if p.pos < p.src.len && (p.src[p.pos] == `i` || p.src[p.pos] == `I`) {
		insensitive = true
		p.pos++
		p.skip_spaces()
	}
	if p.pos >= p.src.len || p.src[p.pos] != `]` {
		return error('attribute end')
	}
	p.pos++
	return p.add(VselMatcher{
		kind:        .attribute
		value:       name
		operator:    operator
		attr_value:  value
		insensitive: insensitive
	})
}

fn (mut p VselParser) pseudo() !int {
	start := p.pos
	p.pos++
	if p.pos < p.src.len && p.src[p.pos] == `:` {
		p.pos++
	}
	p.ident()!
	name := p.src[start..p.pos]
	mut args_start := -1
	if p.pos < p.src.len && p.src[p.pos] == `(` {
		p.pos++
		args_start = p.pos
	}
	match name {
		':not', ':is', ':where', ':has' {
			if args_start < 0 {
				// Without arguments upstream matches nothing (:not, everything).
				list := p.add(VselMatcher{
					kind: .any
				})
				return p.add(VselMatcher{
					kind: if name == ':not' { VselKind.not_ } else { VselKind.any }
					list: [list]
				})
			}
			if name == ':has' {
				return p.has_list()
			}
			list := p.selector_list(true)!
			p.pos++
			return p.add(VselMatcher{
				kind: if name == ':not' { VselKind.not_ } else { VselKind.any }
				list: [list]
			})
		}
		':empty' {
			p.skip_args(args_start)!
			return p.add(VselMatcher{
				kind: .empty
			})
		}
		':nth-child', ':nth-last-child', ':nth-of-type', ':nth-last-of-type' {
			if args_start < 0 {
				return error("!Cannot parse An+B micro syntax (:nth-xxx() argument): ''.")
			}
			p.skip_args(args_start)!
			argument := js_trim(p.src[args_start..p.pos - 1].to_lower())
			a, b := vsel_parse_nth(argument) or {
				return error("!Cannot parse An+B micro syntax (:nth-xxx() argument): '${argument}'.")
			}
			return p.add(VselMatcher{
				kind:  if name.ends_with('of-type') { VselKind.position_of_type } else { VselKind.position }
				nth_a: a
				nth_b: b
				last:  name.contains('-last-')
			})
		}
		':first-child', ':last-child', ':only-child', ':first-of-type', ':last-of-type',
		':only-of-type' {
			p.skip_args(args_start)!
			return p.add(VselMatcher{
				kind:  if name.ends_with('of-type') { VselKind.position_of_type } else { VselKind.position }
				nth_a: 0
				nth_b: 1
				last:  name.starts_with(':last')
				only:  name.starts_with(':only')
			})
		}
		else {
			p.skip_args(args_start)!
			return error('!Unsupported pseudo selector: ${name}.')
		}
	}
}

// skip_args skips the arguments of a pseudo-class, up to its `)`.
fn (mut p VselParser) skip_args(args_start int) ! {
	if args_start < 0 {
		return
	}
	mut depth := 1
	for p.pos < p.src.len {
		if p.src[p.pos] == `(` {
			depth++
		} else if p.src[p.pos] == `)` {
			depth--
			if depth == 0 {
				p.pos++
				return
			}
		}
		p.pos++
	}
	return error('unclosed')
}

// has_list parses the relative selectors of :has(…).
fn (mut p VselParser) has_list() !int {
	mut list := []int{}
	mut from_after := []bool{}
	for {
		p.skip_spaces()
		nodes := p.selector_nodes()!
		from_after << (nodes.len > 0 && nodes[0].comb in ['+', '~'])
		list << p.selector_matcher(nodes)!
		if p.pos < p.src.len && p.src[p.pos] == `,` {
			p.pos++
			continue
		}
		break
	}
	if p.pos >= p.src.len || p.src[p.pos] != `)` {
		return error('unclosed')
	}
	p.pos++
	return p.add(VselMatcher{
		kind:       .has
		list:       list
		from_after: from_after
	})
}

// vsel_parse_nth ports nth-check's parse: (a, b) of An+B.
fn vsel_parse_nth(text string) ?(int, int) {
	formula := text.trim(' \t\n\r\f').to_lower()
	if formula == 'even' {
		return 2, 0
	}
	if formula == 'odd' {
		return 2, 1
	}
	mut r := VselNthReader{
		f: formula
	}
	mut a := 0
	mut sign := r.sign()
	mut number := r.number()
	if r.idx < formula.len && formula[r.idx] == `n` {
		r.idx++
		a = sign * (number or { 1 })
		r.skip_whitespace()
		if r.idx < formula.len {
			sign = r.sign()
			r.skip_whitespace()
			number = r.number()
		} else {
			sign = 0
			number = 0
		}
	}
	n := number or { return none }
	if r.idx < formula.len {
		return none
	}
	return a, sign * n
}

struct VselNthReader {
	f string
mut:
	idx int
}

fn (mut r VselNthReader) sign() int {
	if r.idx < r.f.len && r.f[r.idx] == `-` {
		r.idx++
		return -1
	}
	if r.idx < r.f.len && r.f[r.idx] == `+` {
		r.idx++
	}
	return 1
}

fn (mut r VselNthReader) number() ?int {
	start := r.idx
	mut value := 0
	for r.idx < r.f.len && r.f[r.idx] >= `0` && r.f[r.idx] <= `9` {
		value = value * 10 + int(r.f[r.idx] - `0`)
		r.idx++
	}
	return if r.idx == start { none } else { value }
}

fn (mut r VselNthReader) skip_whitespace() {
	for r.idx < r.f.len && r.f[r.idx] in [`\t`, `\n`, `\f`, `\r`, ` `] {
		r.idx++
	}
}

// vsel_nth_test is nth-check's compile: whether the 0-based index matches An+B.
fn vsel_nth_test(a int, b0 int, index int) bool {
	b := b0 - 1
	if b < 0 && a <= 0 {
		return false
	}
	if a == -1 {
		return index <= b
	}
	if a == 0 {
		return index == b
	}
	if a == 1 {
		return b < 0 || index >= b
	}
	abs_a := if a < 0 { -a } else { a }
	b_mod := ((b % abs_a) + abs_a) % abs_a
	return if a > 1 {
		index >= b && index % abs_a == b_mod
	} else {
		index <= b && index % abs_a == b_mod
	}
}

// vsel_test is selector.test(element).
fn (c &Checker) vsel_test(s &VselSelector, element int) bool {
	if s.root < 0 {
		return false
	}
	return c.vsel_match(s, s.root, element, -1)
}

fn (c &Checker) vsel_elements(parent int) []int {
	doc := c.vue.doc
	return doc.nodes[parent].children.filter(doc.nodes[it].typ == .v_element)
}

fn (c &Checker) vsel_attribute_value(element int, name string) ?string {
	attr := c.vue_get_attribute(element, name, none)
	if attr < 0 {
		return none
	}
	value := c.vue.doc.nodes[attr].value
	return if value >= 0 { c.vue.doc.nodes[value].text } else { '' }
}

fn (c &Checker) vsel_match(s &VselSelector, m int, element int, subject int) bool {
	doc := c.vue.doc
	matcher := &s.matchers[m]
	match matcher.kind {
		.never {
			return false
		}
		.tag {
			return doc.nodes[element].raw_name == matcher.value
		}
		.universal {
			return true
		}
		.class_name {
			value := c.vsel_attribute_value(element, 'class') or { return false }
			return vue_split_whitespace(value).contains(matcher.value)
		}
		.id {
			value := c.vsel_attribute_value(element, 'id') or { return false }
			return value == matcher.value
		}
		.attribute {
			attr_value := c.vsel_attribute_value(element, matcher.value) or { return false }
			if matcher.operator == '' {
				return true
			}
			val := if matcher.insensitive { vsel_lower(matcher.attr_value) } else { matcher.attr_value }
			attr := if matcher.insensitive { vsel_lower(attr_value) } else { attr_value }
			return match matcher.operator {
				'=' { attr == val }
				'~=' { vue_split_whitespace(attr).contains(val) }
				'|=' { attr == val || attr.starts_with('${val}-') }
				'^=' { attr.starts_with(val) }
				'$=' { attr.ends_with(val) }
				'*=' { attr.contains(val) }
				else { false }
			}
		}
		.compound {
			return c.vsel_match(s, matcher.a, element, subject)
				&& c.vsel_match(s, matcher.b, element, subject)
		}
		.subject {
			return element == subject
		}
		.combination {
			if !c.vsel_match(s, matcher.b, element, -1) {
				return false
			}
			parent := doc.nodes[element].parent
			match matcher.comb {
				' ' {
					mut p := parent
					for p >= 0 && doc.nodes[p].typ == .v_element {
						if c.vsel_match(s, matcher.a, p, subject) {
							return true
						}
						p = doc.nodes[p].parent
					}
					return false
				}
				'>' {
					return parent >= 0 && doc.nodes[parent].typ == .v_element
						&& c.vsel_match(s, matcher.a, parent, subject)
				}
				'+', '~' {
					if parent < 0 {
						return false
					}
					siblings := c.vsel_elements(parent)
					index := siblings.index(element)
					before := if index > 0 { siblings[..index] } else { []int{} }
					if matcher.comb == '+' {
						return before.len > 0 && c.vsel_match(s, matcher.a, before.last(), subject)
					}
					return before.any(c.vsel_match(s, matcher.a, it, subject))
				}
				else {
					return false
				}
			}
		}
		.any {
			return matcher.list.any(c.vsel_match(s, it, element, subject))
		}
		.not_ {
			return !matcher.list.any(c.vsel_match(s, it, element, subject))
		}
		.has {
			for k, sel in matcher.list {
				mut queue := []int{}
				if matcher.from_after[k] {
					parent := doc.nodes[element].parent
					if parent >= 0 {
						siblings := c.vsel_elements(parent)
						index := siblings.index(element)
						queue << siblings[index + 1..]
					}
				} else {
					queue << c.vsel_elements(element)
				}
				for queue.len > 0 {
					el := queue[0]
					queue.delete(0)
					if c.vsel_match(s, sel, el, element) {
						return true
					}
					queue << c.vsel_elements(el)
				}
			}
			return false
		}
		.empty {
			return doc.nodes[element].children.all(doc.nodes[it].typ == .v_text
				&& js_trim(doc.nodes[it].text) == '')
		}
		.position, .position_of_type {
			parent := doc.nodes[element].parent
			if parent < 0 {
				return false
			}
			mut elements := c.vsel_elements(parent)
			if matcher.kind == .position_of_type {
				name := doc.nodes[element].raw_name
				elements = elements.filter(doc.nodes[it].raw_name == name)
			}
			index := elements.index(element)
			if matcher.only {
				return index == 0 && elements.len == 1
			}
			i := if matcher.last { elements.len - index - 1 } else { index }
			return vsel_nth_test(matcher.nth_a, matcher.nth_b, i)
		}
	}
}

fn vsel_lower(s string) string {
	return utf16_to_string(jsregexp.js_to_lower(utf16_units(s)))
}
