module jsregexp

// JsRegex is `new RegExp(pattern, flags)` with flags among `imsu` (the ones esquery's selectors
// allow): with `u` the pattern is read in the `u` mode over the code points of the text, and
// without it with the syntax of Annex B over the UTF-16 units. The flags `i`, `m` and `s` are
// those the parsers already know for modifiers (`(?ims:…)`), in effect from the start.
pub struct JsRegex {
	unicode bool
	prog    RegexpProgram
}

// js_regex_new ports `new RegExp(pattern, flags)`: an error when V8 throws (also for a repeated
// flag), or when the matcher does not support the pattern.
pub fn js_regex_new(pattern string, flags string) !JsRegex {
	units := utf16_units(pattern)
	regexp_new(units, flags) or { return error('Invalid regular expression: /${pattern}/${flags}') }
	icase := flags.contains('i')
	multiline := flags.contains('m')
	dot_all := flags.contains('s')
	if flags.contains('u') {
		src := regexp_chars(units, .unicode)
		mut p := RxParser{
			src:              src
			names:            rx_group_names(src)
			icase:            icase
			multiline:        multiline
			dot_all:          dot_all
			last_group_icase: icase
		}
		root := p.disjunction()!
		return JsRegex{
			unicode: true
			prog:    rx_program(root, p.group)!
		}
	}
	src := units.map(u32(it))
	mut p := RxLegacyParser{
		src:       src
		names:     rx_group_names(src)
		captures:  rx_count_captures(src)
		icase:     icase
		multiline: multiline
		dot_all:   dot_all
	}
	root := p.disjunction()!
	return JsRegex{
		unicode: false
		prog:    rx_program(root, p.group)!
	}
}

// test ports `regexp.test(text)` on the UTF-16 units of the text (a lone surrogate is a unit of
// its own, and a code point of its own in the `u` mode); an error when the search takes too long.
pub fn (r &JsRegex) test(units []u16) !bool {
	if r.unicode {
		found, _, _, _ := regexp_exec(r.prog, utf16_code_points(units).map(rune(it)), 0)!
		return found
	}
	return regexp_test_annex_b(r.prog, units)
}

// rx_program compiles the tree of a parsed pattern with `groups` capturing groups.
fn rx_program(root RxNode, groups int) !RegexpProgram {
	mut c := RxCompiler{
		slots: 2 * (groups + 1)
	}
	c.emit(root, false)!
	c.insts << RxInst{
		op: .match_
	}
	return RegexpProgram{
		insts:  c.insts
		groups: groups
		slots:  c.slots
	}
}
