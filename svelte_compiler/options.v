module svelte_compiler

// read/options.js: the checks of <svelte:options customElement> that svelte/ does not make
// (svelte-eslint-parser accepts what they reject; compile() runs them at the end of parsing).

fn (b &Builder) validate_options() ! {
	t := &b.c.t
	if b.c.options < 0 {
		return
	}
	for a in t.list(b.c.options, .attributes) {
		if t.typ(a) != 'Attribute' || t.name(a) != 'customElement' {
			continue
		}
		if t.attr_is_true(a) {
			continue
		}
		chunks := t.get_attribute_chunks(a)
		if chunks.len == 0 {
			continue
		}
		if t.typ(chunks[0]) == 'Text' {
			// get_static_value: a Text chunk's data (null when several chunks).
			if chunks.len > 1 {
				return b.at(a, e_svelte_options_invalid_tagname())
			}
			b.validate_tag(a, t.text(chunks[0], .data), true)!
			continue
		}
		expr := t.get(chunks[0], .expression)
		if t.typ(expr) != 'ObjectExpression' {
			if t.typ(expr) == 'Literal' && t.lit_kind(expr) == .null_ {
				continue
			}
			return b.at(a, e_svelte_options_invalid_customelement())
		}
		mut props := map[string]int{}
		for p in t.list(expr, .properties) {
			key := t.get(p, .key)
			if t.typ(p) != 'Property' || t.flag(p, .computed) || t.typ(key) != 'Identifier' {
				return b.at(a, e_svelte_options_invalid_customelement())
			}
			if t.name(key) !in props {
				props[t.name(key)] = t.get(p, .value)
			}
		}
		if tag := props['tag'] {
			// validate_tag gets the [name, value] pair: its error has no position.
			if t.typ(tag) == 'Literal' && t.lit_kind(tag) == .string {
				b.validate_tag(-1, t.text(tag, .value), true)!
			} else {
				return compile_err(e_svelte_options_invalid_tagname(), no_pos, no_pos)
			}
		}
		if p := props['props'] {
			if t.typ(p) != 'ObjectExpression' {
				return b.at(a, e_svelte_options_invalid_customelement_props())
			}
			for property in t.list(p, .properties) {
				key := t.get(property, .key)
				value := t.get(property, .value)
				if t.typ(property) != 'Property' || t.flag(property, .computed)
					|| t.typ(key) != 'Identifier' || t.typ(value) != 'ObjectExpression' {
					return b.at(a, e_svelte_options_invalid_customelement_props())
				}
				for prop in t.list(value, .properties) {
					pk := t.get(prop, .key)
					pv := t.get(prop, .value)
					if t.typ(prop) != 'Property' || t.flag(prop, .computed)
						|| t.typ(pk) != 'Identifier' || t.typ(pv) != 'Literal' {
						return b.at(a, e_svelte_options_invalid_customelement_props())
					}
					match t.name(pk) {
						'type' {
							if !(t.lit_kind(pv) == .string && t.text(pv, .value) in [
								'String',
								'Number',
								'Boolean',
								'Array',
								'Object',
							]) {
								return b.at(a, e_svelte_options_invalid_customelement_props())
							}
						}
						'reflect' {
							if t.lit_kind(pv) != .boolean {
								return b.at(a, e_svelte_options_invalid_customelement_props())
							}
						}
						'attribute' {
							if t.lit_kind(pv) != .string {
								return b.at(a, e_svelte_options_invalid_customelement_props())
							}
						}
						else {
							return b.at(a, e_svelte_options_invalid_customelement_props())
						}
					}
				}
			}
		}
		if shadow := props['shadow'] {
			ok := (t.typ(shadow) == 'Literal' && t.lit_kind(shadow) == .string
				&& t.text(shadow, .value) in ['open', 'none']) || t.typ(shadow) == 'ObjectExpression'
			if !ok {
				return b.at(a, e_svelte_options_invalid_customelement_shadow())
			}
		}
	}
}

fn (b &Builder) at(node int, d Diag) IError {
	return compile_err(d, b.c.t.nodes[node].start, b.c.t.nodes[node].end)
}

fn (b &Builder) validate_tag(attr int, tag string, is_string bool) ! {
	fail := fn [b, attr] (d Diag) IError {
		if attr < 0 {
			return compile_err(d, no_pos, no_pos)
		}
		return b.at(attr, d)
	}
	if !is_string {
		return fail(e_svelte_options_invalid_tagname())
	}
	if tag != '' {
		if !is_valid_tag_name(tag) {
			return fail(e_svelte_options_invalid_tagname())
		}
		if tag in ['annotation-xml', 'color-profile', 'font-face', 'font-face-src', 'font-face-uri',
			'font-face-format', 'font-face-name', 'missing-glyph'] {
			return fail(e_svelte_options_reserved_tagname())
		}
	}
}

// is_valid_tag_name is read/options.js' regex_valid_tag_name.
fn is_valid_tag_name(tag string) bool {
	rs := tag.runes()
	if rs.len == 0 || rs[0] < `a` || rs[0] > `z` {
		return false
	}
	mut hyphen := false
	for r in rs[1..] {
		if r == `-` {
			hyphen = true
			continue
		}
		ok := (r >= `a` && r <= `z`) || (r >= `0` && r <= `9`) || r == `_` || r == `.`
			|| r == 0xb7 || (r >= 0xc0 && r <= 0xd6) || (r >= 0xd8 && r <= 0xf6)
			|| (r >= 0xf8 && r <= 0x37d) || (r >= 0x37f && r <= 0x1fff)
			|| (r >= 0x200c && r <= 0x200d) || (r >= 0x203f && r <= 0x2040)
			|| (r >= 0x2070 && r <= 0x218f) || (r >= 0x2c00 && r <= 0x2fef)
			|| (r >= 0x3001 && r <= 0xd7ff) || (r >= 0xf900 && r <= 0xfdcf)
			|| (r >= 0xfdf0 && r <= 0xfffd) || (r >= 0x10000 && r <= 0xeffff)
		if !ok {
			return false
		}
	}
	return hyphen
}
