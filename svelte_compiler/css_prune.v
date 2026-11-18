module svelte_compiler

// 2-analyze/css/css-prune.js: marks the selectors that may apply to an element as used.

const node_probably_exists = 0
const node_definitely_exists = 1

// RelView is a RelativeSelector as css-prune handles it: the node (`base`, whose metadata it
// shares) or a copy of it with another combinator or fewer selectors, or one of the made-up
// ones (base -2: `&`, base -3: `*`). comb: the combinator node, -1 none, -2 a descendant one.
struct RelView {
	base int
	comb int
	sels []int
}

fn (z &Analyzer) rv(rel int) RelView {
	return RelView{
		base: rel
		comb: z.t.get(rel, .combinator)
		sels: z.sels(rel)
	}
}

fn (z &Analyzer) comb_name(v RelView) string {
	if v.comb == -2 {
		return ' '
	}
	return z.t.name(v.comb)
}

fn (z &Analyzer) rv_global(v RelView) bool {
	return v.base >= 0 && z.sel_global[v.base]
}

fn (z &Analyzer) rv_global_like(v RelView) bool {
	return v.base >= 0 && z.sel_global_like[v.base]
}

struct Pruner {
mut:
	seen        []int
	nesting_sel int
	any_sel     int
}

fn (mut z Analyzer) prune() {
	mut p := Pruner{
		nesting_sel: z.t.new_node('NestingSelector', -1, -1)
		any_sel:     z.t.new_node('TypeSelector', -1, -1)
	}
	z.t.set_str(p.nesting_sel, .name, '&')
	z.t.set_str(p.any_sel, .name, '*')
	z.prune_visit(z.c.css, mut p)
}

fn (mut z Analyzer) prune_visit(node int, mut p Pruner) {
	t := z.t
	match t.typ(node) {
		'Rule' {
			if z.css_global_block[node] {
				z.prune_visit(t.get(node, .prelude), mut p)
				return
			}
		}
		'ComplexSelector' {
			selectors := z.get_relative_selectors(node, p)
			for element in z.elements {
				p.seen.clear()
				if z.apply_selector(selectors, z.css_rule[node] or { -1 }, element, true, 0,
					selectors.len, mut p)
				{
					z.css_used[node] = true
				}
			}
			return
		}
		else {}
	}
	for ch in t.children(node) {
		z.prune_visit(ch, mut p)
	}
}

fn (z &Analyzer) has_nesting_selector(node int) bool {
	if z.t.typ(node) == 'NestingSelector' {
		return true
	}
	for ch in z.t.children(node) {
		if z.has_nesting_selector(ch) {
			return true
		}
	}
	return false
}

fn (z &Analyzer) get_relative_selectors(node int, p Pruner) []RelView {
	mut selectors := z.truncate(node)
	rule := z.css_rule[node] or { -1 }
	if rule >= 0 && (z.css_parent[rule] or { -1 }) >= 0 && selectors.len > 0 {
		mut has_explicit := false
		for s in selectors {
			for sel in s.sels {
				if z.has_nesting_selector(sel) {
					has_explicit = true
				}
			}
			if s.base >= 0 && z.t.get(s.base, .combinator) >= 0
				&& z.has_nesting_selector(z.t.get(s.base, .combinator)) {
				has_explicit = true
			}
			if has_explicit {
				break
			}
		}
		if !has_explicit {
			if selectors[0].comb == -1 {
				selectors[0] = RelView{
					base: selectors[0].base
					comb: -2
					sels: selectors[0].sels
				}
			}
			selectors.insert(0, RelView{
				base: -2
				comb: -1
				sels: [p.nesting_sel]
			})
		}
	}
	return selectors
}

// truncate drops the trailing `:global(...)` selectors.
fn (z &Analyzer) truncate(node int) []RelView {
	t := z.t
	children := t.list(node, .children)
	mut i := -1
	for k := children.len - 1; k >= 0; k-- {
		ch := children[k]
		sels := z.sels(ch)
		first := if sels.len > 0 { sels[0] } else { -1 }
		if !z.sel_global_like[ch] && !(t.typ(first) == 'PseudoClassSelector'
			&& t.name(first) == 'global' && t.get(first, .args) < 0) && !z.sel_global[ch] {
			i = k
			break
		}
	}
	mut out := []RelView{}
	for k in 0 .. i + 1 {
		ch := children[k]
		sels := z.sels(ch)
		has_root := sels.any(t.typ(it) == 'PseudoClassSelector' && t.name(it) == 'root')
		if !has_root || z.sel_global_like[ch] {
			out << z.rv(ch)
		} else {
			out << RelView{
				base: ch
				comb: t.get(ch, .combinator)
				sels: sels.filter(t.typ(it) == 'PseudoClassSelector' && t.name(it) == 'has')
			}
		}
	}
	return out
}

fn (mut z Analyzer) apply_selector(rels []RelView, rule int, element int, backward bool, from int, to int, mut p Pruner) bool {
	if from >= to {
		return false
	}
	selector_index := if backward { to - 1 } else { from }
	rel := rels[selector_index]
	rest_from := if backward { from } else { from + 1 }
	rest_to := if backward { to - 1 } else { to }
	matched := z.relative_selector_might_apply_to_node(rel, rule, element, backward, mut p)
		&& z.apply_combinator(rel, rels, rest_from, rest_to, rule, element, backward, mut p)
	if matched {
		if rel.base >= 0 && !z.is_outer_global(rel.base) {
			z.sel_scoped[rel.base] = true
		}
		z.scoped[element] = true
	}
	return matched
}

fn (mut z Analyzer) apply_combinator(rel RelView, rels []RelView, from int, to int, rule int, node int, backward bool, mut p Pruner) bool {
	comb := if !backward {
		if from < to { rels[from].comb } else { -1 }
	} else {
		rel.comb
	}
	if comb == -1 {
		return true
	}
	name := z.comb_name(RelView{
		comb: comb
	})
	match name {
		' ', '>' {
			is_adjacent := name == '>'
			parents := if !backward {
				z.get_descendant_elements(node, is_adjacent)
			} else {
				z.get_ancestor_elements(node, is_adjacent, mut []int{})
			}
			mut parent_matched := false
			for parent in parents {
				if z.apply_selector(rels, rule, parent, backward, from, to, mut p) {
					parent_matched = true
				}
			}
			return parent_matched || (backward && (!is_adjacent || parents.len == 0)
				&& z.every_is_global(rels, from, to, rule))
		}
		'+', '~' {
			siblings := z.get_possible_element_siblings(node, backward, name == '+', mut []int{})
			mut sibling_matched := false
			for sib in siblings.keys {
				st := z.t.typ(sib)
				if st in ['RenderTag', 'SlotElement', 'Component'] {
					if to - from == 1 && z.rv_global(rels[from]) {
						sibling_matched = true
					}
				} else if z.apply_selector(rels, rule, sib, backward, from, to, mut p) {
					sibling_matched = true
				}
			}
			return sibling_matched || (backward && z.get_element_parent(node) < 0
				&& z.every_is_global(rels, from, to, rule))
		}
		else {
			return true
		}
	}
}

fn (z &Analyzer) every_is_global(rels []RelView, from int, to int, rule int) bool {
	for i in from .. to {
		if !z.prune_is_global(rels[i], rule) {
			return false
		}
	}
	return true
}

// prune_is_global: a `:global(...)` or unscopeable selector, or an `:is(...)`/`:where(...)`
// containing a global one.
fn (z &Analyzer) prune_is_global(sel RelView, rule int) bool {
	if z.rv_global(sel) || z.rv_global_like(sel) {
		return true
	}
	t := z.t
	mut explicitly_global := false
	for s in sel.sels {
		mut selector_list := -1
		mut can_be_global := false
		mut owner := rule
		if t.typ(s) == 'PseudoClassSelector' {
			if (t.name(s) == 'is' || t.name(s) == 'where') && t.get(s, .args) >= 0 {
				selector_list = t.get(s, .args)
			} else {
				can_be_global = z.is_unscoped_pseudo_class(s)
			}
		}
		if t.typ(s) == 'NestingSelector' {
			owner = z.css_parent[rule] or { -1 }
			selector_list = t.get(owner, .prelude)
		}
		mut has_global := false
		if selector_list >= 0 {
			for complex in t.list(selector_list, .children) {
				if t.list(complex, .children).all(z.prune_is_global(z.rv(it), owner)) {
					has_global = true
					break
				}
			}
		}
		explicitly_global = explicitly_global || has_global
		if !has_global && !can_be_global {
			return false
		}
	}
	return explicitly_global || sel.sels.len == 0
}

fn (mut z Analyzer) relative_selector_might_apply_to_node(rel RelView, rule int, element int, backward bool, mut p Pruner) bool {
	t := z.t
	mut include_self := -1
	for selector in rel.sels {
		typ := t.typ(selector)
		name0 := t.name(selector)
		if typ == 'PseudoClassSelector' && name0 == 'has' && t.get(selector, .args) >= 0 {
			if include_self < 0 {
				rules := z.get_parent_rules(rule)
				mut inc := false
				for r in rules {
					for c in t.list(t.get(r, .prelude), .children) {
						if t.list(c, .children).any(z.prune_is_global(z.rv(it), r)) {
							inc = true
						}
					}
				}
				if !inc {
					last := rules.last()
					for c in t.list(t.get(last, .prelude), .children) {
						for r2 in t.list(c, .children) {
							for s in z.sels(r2) {
								if t.typ(s) == 'PseudoClassSelector' && (t.name(s) == 'root'
									|| (t.name(s) == 'global' && t.get(s, .args) >= 0)) {
									inc = true
								}
							}
						}
					}
				}
				include_self = if inc { 1 } else { 0 }
			}
			mut matched := false
			for complex in t.list(t.get(selector, .args), .children) {
				truncated := z.truncate(complex)
				if truncated.len == 0 {
					z.css_used[complex] = true
					matched = true
					continue
				}
				first := truncated[0]
				rest := truncated[1..]
				if include_self == 1 {
					mut including := []RelView{}
					including << RelView{
						base: first.base
						comb: -1
						sels: first.sels
					}
					including << rest
					if z.apply_selector(including, rule, element, false, 0, including.len, mut p) {
						z.css_used[complex] = true
						matched = true
					}
				}
				mut excluding := []RelView{}
				excluding << RelView{
					base: -3
					comb: -1
					sels: [p.any_sel]
				}
				excluding << if first.comb != -1 {
					first
				} else {
					RelView{
						base: first.base
						comb: -2
						sels: first.sels
					}
				}
				excluding << rest
				if z.apply_selector(excluding, rule, element, false, 0, excluding.len, mut p) {
					z.css_used[complex] = true
					matched = true
				}
			}
			if !matched {
				return false
			}
			continue
		}
		if typ == 'Percentage' || typ == 'Nth' {
			continue
		}
		name := if name0.contains('\\') { unescape_css(name0) } else { name0 }
		match typ {
			'PseudoClassSelector' {
				if name == 'host' || name == 'root' {
					return false
				}
				args := t.get(selector, .args)
				if name == 'global' && args >= 0 && rel.sels.len == 1 {
					complex := t.list(args, .children)[0]
					views := t.list(complex, .children).map(z.rv(it))
					return z.apply_selector(views, rule, element, true, 0, views.len, mut p)
				}
				if name == 'global' && args < 0 {
					return true
				}
				if name == 'not' && args >= 0 {
					for complex in t.list(args, .children) {
						z.mark_used_under(complex)
						relative := z.truncate(complex)
						if t.list(complex, .children).len > 1 {
							for s in relative {
								if s.base >= 0 {
									z.sel_scoped[s.base] = true
								}
							}
							mut el := element
							for el >= 0 {
								z.scoped[el] = true
								el = z.get_element_parent(el)
							}
						}
					}
					continue
				}
				if (name == 'is' || name == 'where') && args >= 0 {
					mut matched := false
					for complex in t.list(args, .children) {
						relative := z.truncate(complex)
						if relative.len == 0 {
							z.css_used[complex] = true
							matched = true
						} else if z.apply_selector(relative, rule, element, true, 0, relative.len, mut
							p)
						{
							z.css_used[complex] = true
							matched = true
						} else if t.list(complex, .children).len > 1 {
							z.css_used[complex] = true
							matched = true
							for s in relative {
								if s.base >= 0 {
									z.sel_scoped[s.base] = true
								}
							}
						}
					}
					if !matched {
						return false
					}
				}
			}
			'PseudoElementSelector' {}
			'AttributeSelector' {
				ename := t.name(element).to_lower()
				aname := name0.to_lower()
				whitelisted := (ename == 'details' || ename == 'dialog') && aname == 'open'
				flags := t.text(selector, .flags)
				has_value := t.has(selector, .value)
				value := if has_value { unquote(t.text(selector, .value)) } else { '' }
				ci := flags.contains('i') || (!flags.contains('s') && aname in case_insensitive_attributes)
				if !whitelisted && !z.attribute_matches(element, name0, value, has_value,
					t.text(selector, .matcher), ci) {
					return false
				}
			}
			'ClassSelector' {
				if !z.attribute_matches(element, 'class', name, true, '~=', false) {
					return false
				}
			}
			'IdSelector' {
				if !z.attribute_matches(element, 'id', name, true, '=', false) {
					return false
				}
			}
			'TypeSelector' {
				if t.name(element).to_lower() != name.to_lower() && name != '*'
					&& t.typ(element) != 'SvelteElement' {
					return false
				}
			}
			'NestingSelector' {
				mut matched := false
				parent := z.css_parent[rule] or { -1 }
				for complex in t.list(t.get(parent, .prelude), .children) {
					views := z.get_relative_selectors(complex, p)
					if z.apply_selector(views, parent, element, backward, 0, views.len, mut p)
						|| t.list(complex, .children).all(z.prune_is_global(z.rv(it), parent)) {
						z.css_used[complex] = true
						matched = true
					}
				}
				if !matched {
					return false
				}
			}
			else {}
		}
	}
	return true
}

const case_insensitive_attributes = ['accept-charset', 'autocapitalize', 'autocomplete', 'behavior',
	'charset', 'crossorigin', 'decoding', 'dir', 'direction', 'draggable', 'enctype', 'enterkeyhint',
	'fetchpriority', 'formenctype', 'formmethod', 'formtarget', 'hidden', 'http-equiv', 'inputmode',
	'kind', 'loading', 'method', 'preload', 'referrerpolicy', 'rel', 'rev', 'role', 'rules', 'scope',
	'shape', 'spellcheck', 'target', 'translate', 'type', 'valign', 'wrap']

// unescape_css is name.replace(/\\(.)/g, '$1').
fn unescape_css(s string) string {
	mut out := []u8{}
	mut i := 0
	for i < s.len {
		if s[i] == `\\` && i + 1 < s.len && s[i + 1] != `\n` && s[i + 1] != `\r` {
			i++
			continue
		}
		out << s[i]
		i++
	}
	return out.bytestr()
}

fn unquote(s string) string {
	if s.len > 0 && ((s[0] == s[s.len - 1] && s[0] == `'`) || s[0] == `"`) {
		return if s.len >= 2 { s[1..s.len - 1] } else { '' }
	}
	return s
}

fn (z &Analyzer) get_parent_rules(rule int) []int {
	mut rules := []int{}
	mut r := rule
	for r >= 0 {
		rules << r
		r = z.css_parent[r] or { -1 }
	}
	return rules
}

fn test_attribute(operator string, expected string, ci bool, value string) bool {
	e := if ci { expected.to_lower() } else { expected }
	v := if ci { value.to_lower() } else { value }
	return match operator {
		'=' { v == e }
		'~=' { split_single_whitespace(v).contains(e) }
		'|=' { '${v}-'.starts_with('${e}-') }
		'^=' { v.starts_with(e) }
		'$=' { v.ends_with(e) }
		'*=' { v.contains(e) }
		else { false }
	}
}

// split_single_whitespace is value.split(/\s/).
fn split_single_whitespace(s string) []string {
	mut out := []string{}
	mut cur := []u8{}
	mut i := 0
	for i < s.len {
		if is_js_space(s, i) {
			out << cur.bytestr()
			cur = []
			i += js_space_len(s, i)
			continue
		}
		cur << s[i]
		i++
	}
	out << cur.bytestr()
	return out
}

fn is_ws_start(s string) bool {
	return s.len > 0 && is_js_space(s, 0)
}

fn is_ws_end(s string) bool {
	if s.len == 0 {
		return false
	}
	mut k := s.len - 1
	for k > 0 && s[k] & 0xc0 == 0x80 {
		k--
	}
	return is_js_space(s, k)
}

fn (mut z Analyzer) attribute_matches(node int, name string, expected string, has_expected bool, operator string, ci bool) bool {
	t := z.t
	name_lower := name.to_lower()
	for a in t.list(node, .attributes) {
		at := t.typ(a)
		if at == 'SpreadAttribute' {
			return true
		}
		if at == 'BindDirective' && t.name(a) == name {
			return true
		}
		if at == 'StyleDirective' && name_lower == 'style' {
			return true
		}
		if at == 'ClassDirective' && name_lower == 'class' {
			if operator == '~=' {
				if t.name(a) == expected {
					return true
				}
			} else {
				return true
			}
		}
		if at != 'Attribute' {
			continue
		}
		if t.name(a).to_lower() != name_lower {
			continue
		}
		if t.attr_is_true(a) {
			return operator == ''
		}
		if !has_expected {
			return true
		}
		if t.is_text_attribute(a) {
			matches := test_attribute(operator, expected, ci, t.text_value(a))
			if !matches && (name_lower == 'class' || name_lower == 'style') {
				continue
			}
			return matches
		}
		mut possible := []string{}
		mut prev := []string{}
		for chunk in t.get_attribute_chunks(a) {
			current := z.get_possible_values(chunk, name_lower == 'class') or { return true }
			if prev.len > 0 {
				mut start_with_space := []string{}
				mut remaining := []string{}
				for c in current {
					if is_ws_start(c) {
						start_with_space << c
					} else {
						remaining << c
					}
				}
				if remaining.len > 0 {
					if start_with_space.len > 0 {
						for pv in prev {
							add_unique(mut possible, pv)
						}
					}
					mut combined := []string{}
					for pv in prev {
						for r in remaining {
							combined << pv + r
						}
					}
					prev = combined.clone()
					for c in start_with_space {
						if is_ws_end(c) {
							add_unique(mut possible, c)
						} else {
							prev << c
						}
					}
					continue
				} else {
					for pv in prev {
						add_unique(mut possible, pv)
					}
					prev = []
				}
			}
			for c in current {
				if is_ws_end(c) {
					add_unique(mut possible, c)
				} else {
					prev << c
				}
			}
			if prev.len < current.len {
				prev << ' '
			}
			if prev.len > 20 {
				return true
			}
		}
		for pv in prev {
			add_unique(mut possible, pv)
		}
		for v in possible {
			if test_attribute(operator, expected, ci, v) {
				return true
			}
		}
	}
	return false
}

fn add_unique(mut list []string, s string) {
	if s !in list {
		list << s
	}
}

// ---------------------------------------------------------------------------------------------
// utils.js gather_possible_values / get_possible_values. Values are kept as JavaScript would
// stringify them; `unknown` makes the result unknown.

struct PossibleValues {
mut:
	values  []string
	unknown bool
}

fn (z &Analyzer) gather_possible_values(node int, is_class bool, mut set PossibleValues, is_nested bool) {
	if set.unknown {
		return
	}
	t := z.t
	match t.typ(node) {
		'Literal' {
			add_unique(mut set.values, t.lit_string(node))
		}
		'ConditionalExpression' {
			z.gather_possible_values(t.get(node, .consequent), is_class, mut set, is_nested)
			z.gather_possible_values(t.get(node, .alternate), is_class, mut set, is_nested)
		}
		'LogicalExpression' {
			if t.text(node, .operator) == '&&' {
				mut left := PossibleValues{}
				z.gather_possible_values(t.get(node, .left), is_class, mut left, is_nested)
				if left.unknown {
					if !is_class || !is_nested {
						for v in ['', 'false', 'NaN', '0'] {
							add_unique(mut set.values, v)
						}
					}
				} else {
					for v in z.falsy_literal_values(t.get(node, .left), is_class, is_nested) {
						add_unique(mut set.values, v)
					}
				}
				z.gather_possible_values(t.get(node, .right), is_class, mut set, is_nested)
			} else {
				z.gather_possible_values(t.get(node, .left), is_class, mut set, is_nested)
				z.gather_possible_values(t.get(node, .right), is_class, mut set, is_nested)
			}
		}
		'ArrayExpression' {
			if !is_class {
				set.unknown = true
				return
			}
			for entry in t.list(node, .elements) {
				if entry >= 0 {
					z.gather_possible_values(entry, is_class, mut set, true)
				}
			}
		}
		'ObjectExpression' {
			if !is_class {
				set.unknown = true
				return
			}
			for p in t.list(node, .properties) {
				key := t.get(p, .key)
				if t.typ(p) == 'Property' && !t.flag(p, .computed)
					&& (t.typ(key) == 'Identifier' || t.typ(key) == 'Literal') {
					add_unique(mut set.values, if t.typ(key) == 'Identifier' {
						t.name(key)
					} else {
						t.lit_string(key)
					})
				} else {
					set.unknown = true
				}
			}
		}
		else {
			set.unknown = true
		}
	}
}

// falsy_literal_values: the known values of the left side of `&&` that are falsy and not
// nullish: they are strings (String(value)), so only ''; none for a class attribute's nested
// value.
fn (z &Analyzer) falsy_literal_values(node int, is_class bool, is_nested bool) []string {
	if is_class && is_nested {
		return []
	}
	mut left := PossibleValues{}
	z.gather_possible_values(node, is_class, mut left, is_nested)
	return if '' in left.values { [''] } else { []string{} }
}

fn (z &Analyzer) get_possible_values(chunk int, is_class bool) ?[]string {
	if z.t.typ(chunk) == 'Text' {
		return [z.t.text(chunk, .data)]
	}
	mut set := PossibleValues{}
	z.gather_possible_values(z.t.get(chunk, .expression), is_class, mut set, false)
	if set.unknown {
		return none
	}
	return set.values
}

// ---------------------------------------------------------------------------------------------

fn (z &Analyzer) path_of(node int) []int {
	return z.meta_path[node] or { []int{} }
}

fn (z &Analyzer) get_ancestor_elements(node int, adjacent_only bool, mut seen []int) []int {
	t := z.t
	mut ancestors := []int{}
	path := z.path_of(node)
	mut i := path.len
	for i > 0 {
		i--
		parent := path[i]
		pt := t.typ(parent)
		if pt == 'SnippetBlock' {
			if parent !in seen {
				seen << parent
				for site in z.sites[parent] or { []int{} } {
					ancestors << z.get_ancestor_elements(site, adjacent_only, mut seen)
				}
			}
			break
		}
		if pt == 'RegularElement' || pt == 'SvelteElement' {
			if pt == 'RegularElement' && t.name(parent) == 'option' {
				is_direct_child := ancestors.len == 0
				mut select_element := -1
				for j := path.len - 1; j >= 0; j-- {
					if j < i && t.typ(path[j]) == 'RegularElement' && t.name(path[j]) == 'select' {
						select_element = path[j]
						break
					}
				}
				if select_element >= 0 && (!adjacent_only || is_direct_child) {
					sc := z.find_element(select_element, 'selectedcontent')
					if adjacent_only && is_direct_child && sc >= 0 {
						return [sc, parent]
					} else if sc >= 0 {
						ancestors << sc
					}
				}
			}
			ancestors << parent
			if adjacent_only {
				break
			}
		}
	}
	return ancestors
}

// find_element: the first RegularElement named `name` under `node` (itself included).
fn (z &Analyzer) find_element(node int, name string) int {
	if z.t.typ(node) == 'RegularElement' && z.t.name(node) == name {
		return node
	}
	for ch in z.t.children(node) {
		f := z.find_element(ch, name)
		if f >= 0 {
			return f
		}
	}
	return -1
}

fn (z &Analyzer) get_descendant_elements(node int, adjacent_only bool) []int {
	t := z.t
	mut descendants := []int{}
	mut seen := []int{}
	start := if t.typ(node) == 'RenderTag' { node } else { t.get(node, .fragment) }
	z.walk_descendants(start, adjacent_only, mut descendants, mut seen)
	if t.typ(node) == 'RegularElement' && t.name(node) == 'selectedcontent' {
		path := z.path_of(node)
		mut select_element := -1
		for j := path.len - 1; j >= 0; j-- {
			if t.typ(path[j]) == 'RegularElement' && t.name(path[j]) == 'select' {
				select_element = path[j]
				break
			}
		}
		if select_element >= 0 {
			z.walk_options(select_element, false, adjacent_only, mut descendants, mut seen)
		}
	}
	return descendants
}

fn (z &Analyzer) walk_options(node int, inside_option bool, adjacent_only bool, mut descendants []int, mut seen []int) {
	t := z.t
	if t.typ(node) == 'RegularElement' && t.name(node) == 'option' {
		for ch in t.children(node) {
			z.walk_options(ch, true, adjacent_only, mut descendants, mut seen)
		}
		return
	}
	if inside_option {
		z.walk_descendants(node, adjacent_only, mut descendants, mut seen)
		return
	}
	for ch in t.children(node) {
		z.walk_options(ch, false, adjacent_only, mut descendants, mut seen)
	}
}

// walk_descendants is get_descendant_elements' walk_children (the node itself included).
fn (z &Analyzer) walk_descendants(node int, adjacent_only bool, mut descendants []int, mut seen []int) {
	if node < 0 {
		return
	}
	t := z.t
	typ := t.typ(node)
	if typ == 'RegularElement' || typ == 'SvelteElement' {
		descendants << node
		if !adjacent_only {
			for ch in t.children(node) {
				z.walk_descendants(ch, adjacent_only, mut descendants, mut seen)
			}
		}
		return
	}
	if typ == 'RenderTag' {
		for snippet in z.snippets_of[node] or { []int{} } {
			if snippet in seen {
				continue
			}
			seen << snippet
			z.walk_descendants(t.get(snippet, .body), adjacent_only, mut descendants, mut seen)
		}
		return
	}
	for ch in t.children(node) {
		z.walk_descendants(ch, adjacent_only, mut descendants, mut seen)
	}
}

fn (z &Analyzer) get_element_parent(node int) int {
	path := z.path_of(node)
	for i := path.len - 1; i >= 0; i-- {
		typ := z.t.typ(path[i])
		if typ == 'RegularElement' || typ == 'SvelteElement' {
			return path[i]
		}
	}
	return -1
}

// ExistsMap is an insertion-ordered Map<node, NodeExistsValue>.
struct ExistsMap {
mut:
	keys   []int
	values []int
}

fn (mut m ExistsMap) set(k int, v int) {
	i := m.keys.index(k)
	if i >= 0 {
		m.values[i] = v
	} else {
		m.keys << k
		m.values << v
	}
}

fn (m &ExistsMap) get(k int) int {
	i := m.keys.index(k)
	return if i >= 0 { m.values[i] } else { -1 }
}

fn add_to_map(from ExistsMap, mut to ExistsMap) {
	for k, key in from.keys {
		exist := from.values[k]
		old := to.get(key)
		to.set(key, if old < 0 || exist > old { exist } else { old })
	}
}

fn has_definite_elements(m ExistsMap) bool {
	return m.values.any(it == node_definitely_exists)
}

fn (z &Analyzer) is_block(node int) bool {
	return z.t.typ(node) in ['IfBlock', 'EachBlock', 'AwaitBlock', 'KeyBlock', 'SlotElement']
}

fn (z &Analyzer) get_possible_element_siblings(node int, backward bool, adjacent_only bool, mut seen []int) ExistsMap {
	t := z.t
	mut result := ExistsMap{}
	path := z.path_of(node)
	mut current := node
	mut i := path.len
	for i > 0 {
		i--
		fragment := path[i]
		i--
		nodes := t.list(fragment, .nodes)
		mut j := nodes.index(current) + if backward { -1 } else { 1 }
		for j >= 0 && j < nodes.len {
			n := nodes[j]
			nt := t.typ(n)
			if nt == 'RegularElement' {
				mut has_slot := false
				for a in t.list(n, .attributes) {
					if t.typ(a) == 'Attribute' && t.name(a).to_lower() == 'slot' {
						has_slot = true
					}
				}
				if !has_slot {
					result.set(n, node_definitely_exists)
					if adjacent_only {
						return result
					}
				}
			} else if z.is_block(n) || nt == 'Component' {
				if nt == 'SlotElement' || nt == 'Component' {
					result.set(n, node_probably_exists)
				}
				possible_last_child := z.get_possible_nested_siblings(n, backward, adjacent_only, mut
					[]int{})
				add_to_map(possible_last_child, mut result)
				if adjacent_only && nt != 'Component' && has_definite_elements(possible_last_child) {
					return result
				}
			} else if nt == 'SvelteElement' {
				result.set(n, node_probably_exists)
			} else if nt == 'RenderTag' {
				result.set(n, node_probably_exists)
				for snippet in z.snippets_of[n] or { []int{} } {
					add_to_map(z.get_possible_nested_siblings(snippet, backward, adjacent_only, mut
						[]int{}), mut result)
				}
			}
			j = if backward { j - 1 } else { j + 1 }
		}
		current = if i >= 0 && i < path.len { path[i] } else { -1 }
		if current < 0 {
			break
		}
		ct := t.typ(current)
		if ct in ['Component', 'SvelteComponent', 'SvelteSelf'] {
			continue
		}
		if ct == 'SnippetBlock' {
			if current in seen {
				break
			}
			seen << current
			sites := z.sites[current] or { []int{} }
			for site in sites {
				siblings := z.get_possible_element_siblings(site, backward, adjacent_only, mut
					seen)
				add_to_map(siblings, mut result)
				if adjacent_only && sites.len == 1 && has_definite_elements(siblings) {
					return result
				}
			}
		}
		if !z.is_block(current) {
			break
		}
		if ct == 'EachBlock' && fragment == t.get(current, .body) {
			add_to_map(z.get_possible_nested_siblings(current, backward, adjacent_only, mut
				[]int{}), mut result)
		}
	}
	return result
}

fn (z &Analyzer) get_possible_nested_siblings(node int, backward bool, adjacent_only bool, mut seen []int) ExistsMap {
	t := z.t
	mut fragments := []int{}
	typ := t.typ(node)
	match typ {
		'EachBlock' {
			fragments << t.get(node, .body)
			fragments << t.get(node, .fallback)
		}
		'IfBlock' {
			fragments << t.get(node, .consequent)
			fragments << t.get(node, .alternate)
		}
		'AwaitBlock' {
			fragments << t.get(node, .pending)
			fragments << t.get(node, .then)
			fragments << t.get(node, .catch_)
		}
		'KeyBlock', 'SlotElement' {
			fragments << t.get(node, .fragment)
		}
		'SnippetBlock' {
			if node in seen {
				return ExistsMap{}
			}
			seen << node
			fragments << t.get(node, .body)
		}
		'Component' {
			fragments << t.get(node, .fragment)
			for s in z.snippets_of[node] or { []int{} } {
				fragments << t.get(s, .body)
			}
		}
		else {}
	}
	mut result := ExistsMap{}
	mut exhaustive := typ != 'SlotElement' && typ != 'SnippetBlock'
	for fragment in fragments {
		if fragment < 0 {
			exhaustive = false
			continue
		}
		m := z.loop_child(t.list(fragment, .nodes), backward, adjacent_only, mut seen)
		exhaustive = exhaustive && has_definite_elements(m)
		add_to_map(m, mut result)
	}
	if !exhaustive {
		for k in 0 .. result.values.len {
			result.values[k] = node_probably_exists
		}
	}
	return result
}

fn (z &Analyzer) loop_child(children []int, backward bool, adjacent_only bool, mut seen []int) ExistsMap {
	t := z.t
	mut result := ExistsMap{}
	mut i := if backward { children.len - 1 } else { 0 }
	for i >= 0 && i < children.len {
		child := children[i]
		ct := t.typ(child)
		if ct == 'RegularElement' {
			result.set(child, node_definitely_exists)
			if adjacent_only {
				break
			}
		} else if ct == 'SvelteElement' {
			result.set(child, node_probably_exists)
		} else if ct == 'RenderTag' {
			for snippet in z.snippets_of[child] or { []int{} } {
				add_to_map(z.get_possible_nested_siblings(snippet, backward, adjacent_only, mut
					seen), mut result)
			}
		} else if z.is_block(child) {
			child_result := z.get_possible_nested_siblings(child, backward, adjacent_only, mut
				seen)
			add_to_map(child_result, mut result)
			if adjacent_only && has_definite_elements(child_result) {
				break
			}
		}
		i = if backward { i - 1 } else { i + 1 }
	}
	return result
}
