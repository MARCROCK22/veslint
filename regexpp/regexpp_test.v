module regexpp

// Expected values come from @eslint-community/regexpp 4.12.2; the full differential test is ../main.v.

fn syntax_error(err IError) SyntaxError {
	if err is SyntaxError {
		return err
	}
	panic('not a SyntaxError: ${err}')
}

fn test_validate_pattern_error() {
	src := to_utf16('[')
	validate_pattern(src, 0, src.len, PatternFlags{ unicode: true }, Options{}) or {
		e := syntax_error(err)
		assert e.message == 'Invalid regular expression: /[/u: Unterminated character class'
		assert e.index == 1
		return
	}
	assert false
}

fn test_validate_flags_and_literal_errors() {
	flags := to_utf16('gg')
	validate_flags(flags, 0, flags.len, Options{}) or {
		e := syntax_error(err)
		assert e.message == "Invalid regular expression: Duplicated flag 'g'"
		assert e.index == 0
	}
	lit := to_utf16('/a/gg')
	validate_literal(lit, 0, lit.len, Options{}) or {
		e := syntax_error(err)
		assert e.message == "Invalid regular expression: /a/gg: Duplicated flag 'g'"
		assert e.index == 3
		return
	}
	assert false
}

fn test_events_parse_twice() {
	src := to_utf16('(?<a>\\x1f)')
	r := validate_pattern_events(src, 0, src.len, PatternFlags{}, Options{})
	assert !r.has_error
	got := r.events.filter(it.kind != .pattern_leave).map(if it.kind == .pattern_enter {
		'P${it.start}'
	} else {
		'C${it.start},${it.end},${it.value}'
	})
	assert got == ['P0', 'C5,9,31', 'P0', 'C5,9,31']
}

struct Collector {
mut:
	events []VisitEvent
}

fn test_walk_order() {
	src := to_utf16('a{2,}?|[\\d-z]')
	a := parse_pattern(src, 0, src.len, PatternFlags{}, Options{})!
	mut got := []string{}
	for e in a.visit_events() {
		got << (if e.enter { 'E' } else { 'L' }) + a.nodes[e.node].kind.type_name() + ':' + a.raw(e.node)
	}
	assert got == ['EPattern:a{2,}?|[\\d-z]', 'EAlternative:a{2,}?', 'EQuantifier:a{2,}?',
		'ECharacter:a', 'LCharacter:a', 'LQuantifier:a{2,}?', 'LAlternative:a{2,}?',
		'EAlternative:[\\d-z]', 'ECharacterClass:[\\d-z]', 'ECharacterSet:\\d', 'LCharacterSet:\\d',
		'ECharacter:-', 'LCharacter:-', 'ECharacter:z', 'LCharacter:z', 'LCharacterClass:[\\d-z]',
		'LAlternative:[\\d-z]', 'LPattern:a{2,}?|[\\d-z]']
	// closures capture by value: collect through a reference
	mut c := &Collector{}
	a.walk(fn [mut c] (e VisitEvent) {
		c.events << e
	})
	assert c.events == a.visit_events()
	q := a.nodes[a.nodes[a.nodes[a.root].alternatives[0]].elements[0]]
	assert q.kind == .quantifier && q.min == 2 && quantifier_is_infinite(q.max) && !q.greedy
}
