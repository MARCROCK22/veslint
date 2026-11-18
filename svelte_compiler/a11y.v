module svelte_compiler

// visitors/shared/a11y/index.js: check_element and its helpers.

// StaticValue is get_static_value's result: null, true, or a string.
struct StaticValue {
	null_ bool = true
	true_ bool
	s     string
}

fn (t &Tree) static_value(attr int) StaticValue {
	if attr < 0 {
		return StaticValue{}
	}
	if t.attr_is_true(attr) {
		return StaticValue{
			null_: false
			true_: true
		}
	}
	if t.is_text_attribute(attr) {
		return StaticValue{
			null_: false
			s:     t.text_value(attr)
		}
	}
	return StaticValue{}
}

// static_text_value: the string of a text attribute, none otherwise.
fn (t &Tree) static_text_value(attr int) ?string {
	v := t.static_value(attr)
	if v.null_ || v.true_ {
		return none
	}
	return v.s
}

fn (mut z Analyzer) check_element(node int) {
	t := z.t
	mut attribute_map := map[string]int{}
	mut handlers := []string{}
	mut attributes := []int{}
	is_dynamic := t.typ(node) == 'SvelteElement'
	mut has_spread := false
	mut has_contenteditable_attr := false
	mut has_contenteditable_binding := false
	name := t.name(node)
	for a in t.list(node, .attributes) {
		match t.typ(a) {
			'Attribute' {
				if t.is_event_attribute(a) {
					h := t.name(a)[2..]
					if h !in handlers {
						handlers << h
					}
				} else {
					attributes << a
					attribute_map[t.name(a)] = a
					if t.name(a) == 'contenteditable' {
						has_contenteditable_attr = true
					}
				}
			}
			'SpreadAttribute' {
				has_spread = true
			}
			'BindDirective' {
				if is_content_editable_binding(t.name(a)) {
					has_contenteditable_binding = true
				}
			}
			'OnDirective' {
				if t.name(a) !in handlers {
					handlers << t.name(a)
				}
			}
			else {}
		}
	}
	interactivity := z.element_interactivity(name, attribute_map)
	is_interactive := interactivity == 'interactive'
	is_non_interactive := interactivity == 'non-interactive'
	is_static := interactivity == 'static'
	for a in t.list(node, .attributes) {
		if t.typ(a) != 'Attribute' {
			continue
		}
		aname := t.name(a).to_lower()
		if aname.starts_with('aria-') {
			if name in invisible_elements {
				z.warn(a, w_a11y_aria_attributes(name))
			}
			typ := aname[5..]
			if typ !in aria_attributes {
				z.warn(a, w_a11y_unknown_aria_attribute(typ, fuzzymatch(typ, aria_attributes)))
			}
			if aname == 'aria-hidden' && is_heading_tag(name) {
				z.warn(a, w_a11y_hidden(name))
			}
			value := t.static_value(a)
			for p in aria_props {
				if p.name == aname {
					z.validate_aria_attribute_value(a, aname, p, value)
					break
				}
			}
			if aname == 'aria-activedescendant' && !is_dynamic && !is_interactive
				&& 'tabindex' !in attribute_map && !has_spread {
				z.warn(a, w_a11y_aria_activedescendant_has_tabindex())
			}
		}
		match aname {
			'role' {
				if name in invisible_elements {
					z.warn(a, w_a11y_misplaced_role(name))
				}
				value := t.static_value(a)
				if value.null_ || value.true_ {
					// typeof value !== 'string'
				} else {
					for current_role in split_js_whitespace(value.s) {
						if current_role != '' && current_role in abstract_roles {
							z.warn(a, w_a11y_no_abstract_role(current_role))
						} else if current_role != '' && current_role !in aria_roles {
							z.warn(a, w_a11y_unknown_role(current_role, fuzzymatch(current_role,
								aria_roles)))
						}
						implicit := z.get_implicit_role(name, attribute_map) or { '\x00' }
						if current_role == implicit && name !in ['ul', 'ol', 'li', 'menu']
							&& !(name == 'a' && 'href' !in attribute_map) {
							z.warn(a, w_a11y_no_redundant_roles(current_role))
						}
						if !z.is_parent(['section', 'article']) {
							if nested := a11y_nested_implicit_semantics[name] {
								if current_role == nested {
									z.warn(a, w_a11y_no_redundant_roles(current_role))
								}
							}
						}
						if !is_dynamic && !z.is_semantic_role_element(current_role, name, attribute_map) {
							for rd in role_defs {
								if rd.name == current_role {
									mut missing := false
									if !has_spread {
										for prop in rd.required {
											mut found := false
											for x in attributes {
												if t.name(x) == prop {
													found = true
													break
												}
											}
											if !found {
												missing = true
												break
											}
										}
									}
									if missing {
										z.warn(a, w_a11y_role_has_required_aria_props(current_role,
											js_list(rd.required.map('"${it}"'), 'and')))
									}
									break
								}
							}
						}
						if !has_spread && !z.has_disabled_attribute(attribute_map)
							&& !z.is_hidden_from_screen_reader(name, attribute_map)
							&& current_role !in presentation_roles && current_role in interactive_roles
							&& is_static && !z.attr_truthy(attribute_map, 'tabindex') {
							if handlers.any(it in a11y_interactive_handlers) {
								z.warn(node, w_a11y_interactive_supports_focus(current_role))
							}
						}
						if !has_spread && is_interactive && (current_role in non_interactive_roles
							|| current_role in presentation_roles) {
							z.warn(node, w_a11y_no_interactive_element_to_noninteractive_role(name,
								current_role))
						}
						if !has_spread && is_non_interactive && current_role in interactive_roles {
							exceptions := a11y_non_interactive_element_to_interactive_role_exceptions[name] or {
								[]string{}
							}
							if current_role !in exceptions {
								z.warn(node, w_a11y_no_noninteractive_element_to_interactive_role(name,
									current_role))
							}
						}
					}
				}
			}
			'accesskey' {
				z.warn(a, w_a11y_accesskey())
			}
			'autofocus' {
				if name != 'dialog' && !z.is_parent(['dialog']) {
					z.warn(a, w_a11y_autofocus())
				}
			}
			'scope' {
				if !is_dynamic && name != 'th' {
					z.warn(a, w_a11y_misplaced_scope())
				}
			}
			'tabindex' {
				value := t.static_value(a)
				// !isNaN(value) && +value > 0
				if value.true_ {
					// +true is 1
					z.warn(a, w_a11y_positive_tabindex())
				} else if !value.null_ {
					n := js_to_number(value.s)
					if n == n && n > 0 {
						z.warn(a, w_a11y_positive_tabindex())
					}
				}
			}
			else {}
		}
	}
	role := attribute_map['role'] or { -1 }
	role_static := t.static_text_value(role)
	role_static_value := role_static or { '\x00' }
	if 'click' in handlers {
		is_non_presentation_role := role_static != none && role_static_value !in presentation_roles
		if !is_dynamic && !z.is_hidden_from_screen_reader(name, attribute_map)
			&& (role < 0 || is_non_presentation_role) && !is_interactive && !has_spread {
			if 'keydown' !in handlers && 'keyup' !in handlers && 'keypress' !in handlers {
				z.warn(node, w_a11y_click_events_have_key_events(name))
			}
		}
	}
	role_value := if role >= 0 {
		role_static
	} else {
		z.get_implicit_role(name, attribute_map)
	}
	if !is_dynamic && !is_interactive && role_static_value !in interactive_roles {
		tab_index := attribute_map['tabindex'] or { -1 }
		if tab_index >= 0 {
			tv := t.static_text_value(tab_index)
			if tv == none || js_to_number(tv or { '' }) >= 0 {
				z.warn(node, w_a11y_no_noninteractive_tabindex())
			}
		}
	}
	if rv := role_value {
		for rd in role_defs {
			if rd.name == rv {
				is_implicit := rv != '' && role < 0
				for attr in attributes {
					an := t.name(attr)
					mut is_aria := false
					for p in aria_props {
						if p.name == an {
							is_aria = true
							break
						}
					}
					if is_aria && an !in rd.props {
						if is_implicit {
							z.warn(attr, w_a11y_role_supports_aria_props_implicit(an, rv, name))
						} else {
							z.warn(attr, w_a11y_role_supports_aria_props(an, rv))
						}
					}
				}
				break
			}
		}
	}
	if !has_spread && !has_contenteditable_attr && !z.is_hidden_from_screen_reader(name, attribute_map)
		&& role_static_value !in presentation_roles && ((!is_interactive
		&& role_static_value in non_interactive_roles) || (is_non_interactive && role < 0)) {
		if handlers.any(it in a11y_recommended_interactive_handlers) {
			z.warn(node, w_a11y_no_noninteractive_element_interactions(name))
		}
	}
	if !has_spread && (role < 0 || role_static != none)
		&& !z.is_hidden_from_screen_reader(name, attribute_map)
		&& role_static_value !in presentation_roles && !is_interactive
		&& role_static_value !in interactive_roles && !is_non_interactive
		&& role_static_value !in non_interactive_roles && role_static_value !in abstract_roles {
		interactive := handlers.filter(it in a11y_interactive_handlers)
		if interactive.len > 0 {
			z.warn(node, w_a11y_no_static_element_interactions(name, js_list(interactive, 'or')))
		}
	}
	if !has_spread && 'mouseover' in handlers && 'focus' !in handlers {
		z.warn(node, w_a11y_mouse_events_have_key_events('mouseover', 'focus'))
	}
	if !has_spread && 'mouseout' in handlers && 'blur' !in handlers {
		z.warn(node, w_a11y_mouse_events_have_key_events('mouseout', 'blur'))
	}
	is_labelled := 'aria-label' in attribute_map || 'aria-labelledby' in attribute_map
		|| 'title' in attribute_map
	match name {
		'a', 'button' {
			hidden := t.static_value(attribute_map['aria-hidden'] or { -1 })
			inert := t.static_value(attribute_map['inert'] or { -1 })
			is_hidden := (!hidden.null_ && !hidden.true_ && hidden.s == 'true') || !inert.null_
			if !has_spread && !is_hidden && !is_labelled && !z.has_content(node) {
				z.warn(node, w_a11y_consider_explicit_label())
			}
			if name == 'a' {
				// (an if-guard `h` as an if expression's value takes the type of the earlier `h`: V bug 20)
				mut href := attribute_map['href'] or { -1 }
				if href < 0 {
					href = attribute_map['xlink:href'] or { -1 }
				}
				if href >= 0 {
					if hv := t.static_text_value(href) {
						if hv == '' || hv == '#' || is_js_prefix(hv) {
							z.warn(href, w_a11y_invalid_attribute(hv, t.name(href)))
						}
					}
				} else if !has_spread {
					id := t.static_value(attribute_map['id'] or { -1 })
					nm := t.static_value(attribute_map['name'] or { -1 })
					ad := t.static_value(attribute_map['aria-disabled'] or { -1 })
					if !static_truthy(id) && !static_truthy(nm) && !(!ad.null_ && !ad.true_
						&& ad.s == 'true') {
						z.warn_missing_attribute(node, ['href'], name)
					}
				}
			}
		}
		'input' {
			typ := attribute_map['type'] or { -1 }
			type_value := t.static_text_value(typ)
			if (type_value or { '\x00' }) == 'image' && !has_spread {
				required := ['alt', 'aria-label', 'aria-labelledby']
				if !required.any(it in attribute_map) {
					z.warn_missing_attribute(node, required, 'input type="image"')
				}
			}
			autocomplete := attribute_map['autocomplete'] or { -1 }
			if typ >= 0 && autocomplete >= 0 {
				av := t.static_value(autocomplete)
				if !is_valid_autocomplete(av) {
					z.warn(autocomplete, w_a11y_autocomplete_valid(if av.true_ {
						'true'
					} else {
						av.s
					},
						type_value or { '...' }))
				}
			}
		}
		'img' {
			alt := t.static_text_value(attribute_map['alt'] or { -1 }) or { '' }
			aria_hidden := t.static_value(attribute_map['aria-hidden'] or { -1 })
			if alt != '' && !static_truthy(aria_hidden) && !has_spread {
				if is_redundant_img_alt(alt) {
					z.warn(node, w_a11y_img_redundant_alt())
				}
			}
		}
		'label' {
			if !has_spread && 'for' !in attribute_map && !z.has_input_child(node) {
				z.warn(node, w_a11y_label_has_associated_control())
			}
		}
		'video' {
			ah := attribute_map['aria-hidden'] or { -1 }
			ahv := t.static_value(ah)
			if 'muted' in attribute_map || (ah >= 0 && !ahv.null_ && !ahv.true_ && ahv.s == 'true')
				|| has_spread {
				return
			}
			if 'src' !in attribute_map {
				return
			}
			mut has_caption := false
			for ch in t.list(t.get(node, .fragment), .nodes) {
				if t.typ(ch) == 'RegularElement' && t.name(ch) == 'track' {
					for x in t.list(ch, .attributes) {
						if t.typ(x) == 'SpreadAttribute' || (t.typ(x) == 'Attribute'
							&& t.name(x) == 'kind' && (t.static_text_value(x) or { '' }) == 'captions') {
							has_caption = true
						}
					}
					break
				}
			}
			if !has_caption {
				z.warn(node, w_a11y_media_has_caption())
			}
		}
		'figcaption' {
			if !z.is_parent(['figure']) {
				z.warn(node, w_a11y_figcaption_parent())
			}
		}
		'figure' {
			mut children := []int{}
			for ch in t.list(t.get(node, .fragment), .nodes) {
				if t.typ(ch) == 'Comment' {
					continue
				}
				if t.typ(ch) == 'Text' && !is_not_whitespace_text(t.text(ch, .data)) {
					continue
				}
				children << ch
			}
			mut index := -1
			for k, ch in children {
				if t.typ(ch) == 'RegularElement' && t.name(ch) == 'figcaption' {
					index = k
					break
				}
			}
			if index != -1 && index != 0 && index != children.len - 1 {
				z.warn(children[index], w_a11y_figcaption_index())
			}
		}
		else {}
	}
	if !has_spread && name != 'a' {
		if required := a11y_required_attributes[name] {
			if !required.any(it in attribute_map) {
				z.warn_missing_attribute(node, required, name)
			}
		}
	}
	if name in a11y_distracting_elements {
		z.warn(node, w_a11y_distracting_elements(name))
	}
	if !has_spread && !is_labelled && !has_contenteditable_binding && name in a11y_required_content
		&& !z.has_content(node) {
		z.warn(node, w_a11y_missing_content(name))
	}
}

fn static_truthy(v StaticValue) bool {
	return !v.null_ && (v.true_ || v.s != '')
}

fn (z &Analyzer) attr_truthy(m map[string]int, name string) bool {
	return name in m
}

fn is_heading_tag(name string) bool {
	return name.len == 2 && name[0] == `h` && name[1] >= `1` && name[1] <= `6`
}

// is_js_prefix is /^\W*javascript:/i.
fn is_js_prefix(s string) bool {
	mut i := 0
	for i < s.len && !((s[i] >= `a` && s[i] <= `z`) || (s[i] >= `A` && s[i] <= `Z`)
		|| (s[i] >= `0` && s[i] <= `9`) || s[i] == `_`) {
		i++
	}
	return s[i..].to_lower().starts_with('javascript:')
}

// is_redundant_img_alt is /\b(image|picture|photo)\b/i.
fn is_redundant_img_alt(s string) bool {
	low := s.to_lower()
	for word in ['image', 'picture', 'photo'] {
		mut from := 0
		for {
			i := low.index_after(word, from) or { break }
			before_ok := i == 0 || !is_word_byte(low[i - 1])
			after := i + word.len
			after_ok := after >= low.len || !is_word_byte(low[after])
			if before_ok && after_ok {
				return true
			}
			from = i + 1
		}
	}
	return false
}

fn is_word_byte(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) || c == `_`
}

// split_js_whitespace is value.split(/\s+/).
fn split_js_whitespace(s string) []string {
	mut out := []string{}
	mut cur := []u8{}
	mut i := 0
	mut in_ws := false
	for i < s.len {
		if is_js_space(s, i) {
			n := js_space_len(s, i)
			if !in_ws {
				out << cur.bytestr()
				cur = []
				in_ws = true
			}
			i += n
			continue
		}
		in_ws = false
		cur << s[i]
		i++
	}
	out << cur.bytestr()
	return out
}

// js_list is utils/string.js list(): `a`, `a or b`, `a, b or c`.
fn js_list(strings []string, conjunction string) string {
	if strings.len == 1 {
		return strings[0]
	}
	if strings.len == 2 {
		return '${strings[0]} ${conjunction} ${strings[1]}'
	}
	return '${strings[..strings.len - 1].join(', ')} ${conjunction} ${strings.last()}'
}

// js_to_number is JavaScript's Number(string) (+value).
fn js_to_number(s string) f64 {
	trimmed := s.trim(' \t\n\r\v\f')
	if trimmed == '' {
		return 0
	}
	if trimmed in ['Infinity', '+Infinity'] {
		return math_inf
	}
	if trimmed == '-Infinity' {
		return -math_inf
	}
	low := trimmed.to_lower()
	if low.starts_with('0x') || low.starts_with('0o') || low.starts_with('0b') {
		base := match low[1] {
			`x` { 16 }
			`o` { 8 }
			else { 2 }
		}
		mut v := 0.0
		for c in low[2..] {
			d := if c >= `0` && c <= `9` {
				int(c - `0`)
			} else if c >= `a` && c <= `f` {
				int(c - `a`) + 10
			} else {
				99
			}
			if d >= base {
				return math_nan
			}
			v = v * base + d
		}
		return if low.len > 2 { v } else { math_nan }
	}
	// A decimal literal: digits, optional fraction, optional exponent.
	mut i := 0
	if i < trimmed.len && (trimmed[i] == `+` || trimmed[i] == `-`) {
		i++
	}
	mut digits := 0
	for i < trimmed.len && trimmed[i] >= `0` && trimmed[i] <= `9` {
		i++
		digits++
	}
	if i < trimmed.len && trimmed[i] == `.` {
		i++
		for i < trimmed.len && trimmed[i] >= `0` && trimmed[i] <= `9` {
			i++
			digits++
		}
	}
	if digits == 0 {
		return math_nan
	}
	if i < trimmed.len && (trimmed[i] == `e` || trimmed[i] == `E`) {
		i++
		if i < trimmed.len && (trimmed[i] == `+` || trimmed[i] == `-`) {
			i++
		}
		mut ed := 0
		for i < trimmed.len && trimmed[i] >= `0` && trimmed[i] <= `9` {
			i++
			ed++
		}
		if ed == 0 {
			return math_nan
		}
	}
	if i != trimmed.len {
		return math_nan
	}
	return trimmed.f64()
}

const math_nan = f64_from_bits(0x7ff8000000000000)
const math_inf = f64_from_bits(0x7ff0000000000000)

fn f64_from_bits(b u64) f64 {
	return unsafe { *(&f64(&b)) }
}

fn (mut z Analyzer) warn_missing_attribute(node int, attributes []string, name string) {
	article := if (attributes[0].len > 0 && attributes[0][0] in [`a`, `e`, `i`, `o`, `u`])
		|| attributes[0] == 'href' {
		'an'
	} else {
		'a'
	}
	sequence := if attributes.len > 1 {
		attributes[..attributes.len - 1].join(', ') + ' or ${attributes.last()}'
	} else {
		attributes[0]
	}
	z.warn(node, w_a11y_missing_attribute(name, article, sequence))
}

fn (z &Analyzer) is_hidden_from_screen_reader(tag string, m map[string]int) bool {
	t := z.t
	if tag == 'input' {
		v := t.static_value(m['type'] or { -1 })
		if !v.null_ && !v.true_ && v.s == 'hidden' {
			return true
		}
	}
	ah := m['aria-hidden'] or { return false }
	v := t.static_value(ah)
	if v.null_ {
		return true
	}
	return v.true_ || v.s == 'true'
}

fn (z &Analyzer) has_disabled_attribute(m map[string]int) bool {
	t := z.t
	if static_truthy(t.static_value(m['disabled'] or { -1 })) {
		return true
	}
	if ad := m['aria-disabled'] {
		v := t.static_value(ad)
		if !v.null_ && !v.true_ && v.s == 'true' {
			return true
		}
	}
	return false
}

fn (z &Analyzer) match_schema(schema Schema, tag string, m map[string]int) bool {
	if schema.name != tag {
		return false
	}
	if !schema.has_attributes {
		return true
	}
	for sa in schema.attributes {
		attr := m[sa.name] or { return false }
		if sa.has_value && sa.value != '' && sa.value != (z.t.static_text_value(attr) or { '\x00' }) {
			return false
		}
	}
	return true
}

fn (z &Analyzer) element_interactivity(tag string, m map[string]int) string {
	for s in interactive_element_role_schemas {
		if z.match_schema(s, tag, m) {
			return 'interactive'
		}
	}
	if tag != 'header' {
		for s in non_interactive_element_role_schemas {
			if z.match_schema(s, tag, m) {
				return 'non-interactive'
			}
		}
	}
	for s in interactive_element_ax_object_schemas {
		if z.match_schema(s, tag, m) {
			return 'interactive'
		}
	}
	for s in non_interactive_element_ax_object_schemas {
		if z.match_schema(s, tag, m) {
			return 'non-interactive'
		}
	}
	return 'static'
}

fn (z &Analyzer) is_semantic_role_element(role string, tag string, m map[string]int) bool {
	for e in element_ax_objects {
		if e.schema.name != tag {
			continue
		}
		mut ok := true
		if e.schema.has_attributes {
			for sa in e.schema.attributes {
				attr := m[sa.name] or {
					ok = false
					break
				}
				v := z.t.static_value(attr)
				// get_static_value(...) === attr.value
				if v.null_ || v.true_ || !sa.has_value || v.s != sa.value {
					ok = false
					break
				}
			}
		}
		if ok && role in e.roles {
			return true
		}
	}
	return false
}

fn is_valid_autocomplete(v StaticValue) bool {
	if v.true_ {
		return false
	}
	if v.null_ || v.s == '' {
		return true
	}
	mut tokens := split_js_whitespace(v.s.trim_space().to_lower())
	if tokens.len > 0 && tokens[0].starts_with('section-') {
		tokens.delete(0)
	}
	if tokens.len > 0 && tokens[0] in address_type_tokens {
		tokens.delete(0)
	}
	if tokens.len > 0 && tokens[0] in autofill_field_name_tokens {
		tokens.delete(0)
	} else {
		if tokens.len > 0 && tokens[0] in contact_type_tokens {
			tokens.delete(0)
		}
		if tokens.len > 0 && tokens[0] in autofill_contact_field_name_tokens {
			tokens.delete(0)
		} else {
			return false
		}
	}
	if tokens.len > 0 && tokens[0] == 'webauthn' {
		tokens.delete(0)
	}
	return tokens.len == 0
}

fn (z &Analyzer) get_implicit_role(name string, m map[string]int) ?string {
	t := z.t
	if name == 'menuitem' {
		ta := m['type'] or { return none }
		typ := t.static_text_value(ta) or { return none }
		if typ == '' {
			return none
		}
		return menuitem_type_to_implicit_role[typ] or { return none }
	} else if name == 'input' {
		ta := m['type'] or { return none }
		typ := t.static_text_value(ta) or { return none }
		if typ == '' {
			return none
		}
		if 'list' in m && typ in combobox_if_list {
			return 'combobox'
		}
		return input_type_to_implicit_role[typ] or { return none }
	}
	return a11y_implicit_semantics[name] or { return none }
}

fn (z &Analyzer) has_content(element int) bool {
	t := z.t
	for n in t.list(t.get(element, .fragment), .nodes) {
		typ := t.typ(n)
		if typ == 'Text' {
			if t.text(n, .data).trim_space() == '' {
				continue
			}
		}
		if typ == 'RegularElement' || typ == 'SvelteElement' {
			mut popover := false
			mut has_alt := false
			for a in t.list(n, .attributes) {
				if t.typ(a) == 'Attribute' && t.name(a) == 'popover' {
					popover = true
				}
				if t.typ(a) == 'Attribute' && t.name(a) == 'alt' {
					has_alt = true
				}
			}
			if popover {
				continue
			}
			if t.name(n) == 'img' && has_alt {
				return true
			}
			if t.name(n) == 'selectedcontent' {
				return true
			}
			if !z.has_content(n) {
				continue
			}
		}
		return true
	}
	return false
}

fn (z &Analyzer) is_parent(elements []string) bool {
	for i := z.path.len - 1; i >= 0; i-- {
		p := z.path[i]
		typ := z.t.typ(p)
		if typ == 'SvelteElement' {
			return true
		}
		if typ == 'RegularElement' {
			return z.t.name(p) in elements
		}
	}
	return false
}

fn (z &Analyzer) has_input_child(node int) bool {
	t := z.t
	typ := t.typ(node)
	if typ in ['SvelteElement', 'SlotElement', 'Component', 'RenderTag']
		|| (typ == 'RegularElement' && (t.name(node) in a11y_labelable || t.name(node) == 'slot')) {
		return true
	}
	for ch in t.children(node) {
		if z.has_input_child(ch) {
			return true
		}
	}
	return false
}

fn (mut z Analyzer) validate_aria_attribute_value(attr int, name string, schema AriaProp, v StaticValue) {
	if v.null_ {
		return
	}
	value := if v.true_ { '' } else { v.s }
	match schema.typ {
		'id', 'string' {
			if value == '' {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type(name, 'non-empty string'))
			}
		}
		'number' {
			n := js_to_number(value)
			if value == '' || n != n {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type(name, 'number'))
			}
		}
		'boolean' {
			if value != 'true' && value != 'false' {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type_boolean(name))
			}
		}
		'idlist' {
			if value == '' {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type_idlist(name))
			}
		}
		'integer' {
			n := js_to_number(value)
			if value == '' || n != n || n != f64(i64(n)) || n > 9e15 || n < -9e15 {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type_integer(name))
			}
		}
		'token' {
			if value.to_lower() !in schema.values {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type_token(name, js_list(schema.values.map('"${it}"'),
					'or')))
			}
		}
		'tokenlist' {
			for part in split_js_whitespace(value.to_lower()) {
				if part !in schema.values {
					z.warn(attr, w_a11y_incorrect_aria_attribute_type_tokenlist(name,
						js_list(schema.values.map('"${it}"'), 'or')))
					break
				}
			}
		}
		'tristate' {
			if value != 'true' && value != 'false' && value != 'mixed' {
				z.warn(attr, w_a11y_incorrect_aria_attribute_type_tristate(name))
			}
		}
		else {}
	}
}
