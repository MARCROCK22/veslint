module rules

import jsregexp

// node-semver 7.8.6 (the semver eslint-plugin-vue 10.12.1 resolves), the part
// vue/no-unsupported-features uses: `new Range(text)` without options (classes/range.js,
// classes/comparator.js, classes/semver.js, internal/re.js with its "safe" regular expressions,
// internal/trim-comparator-whitespace.js) and `subset(sub, dom)` (ranges/subset.js). The regular
// expressions are re.js's own, run by jsregexp; an invalid range is an error (Range throws).

const vsem_max_length = 256
const vsem_max_safe_integer = i64(9007199254740991)
const vsem_ldn = '[a-zA-Z0-9-]'

// vsem_safe is makeSafeRegex for `\s`: `\s*` matches at most one white space and `\s+` exactly
// one. Its bounds on `\d` (256) and `[a-zA-Z0-9-]` (250) make programs too large for jsregexp and
// are left out: they only fail a number of more than 256 digits or an identifier of more than 250
// characters, which SemVer rejects anyway (MAX_SAFE_INTEGER, MAX_LENGTH), so the range is invalid
// either way.
fn vsem_safe(value string) string {
	return value.replace('\\s*', '\\s{0,1}').replace('\\s+', '\\s{1,1}')
}

// VsemRe holds the regular expressions of re.js a Range needs (safeRe, except build_strip, which
// is range.js's BUILDSTRIPRE from the unbounded source).
struct VsemRe {
	full        jsregexp.JsRegex
	comparator  jsregexp.JsRegex
	hyphen      jsregexp.JsRegex
	tilde_trim  jsregexp.JsRegex
	caret_trim  jsregexp.JsRegex
	tilde       jsregexp.JsRegex
	caret       jsregexp.JsRegex
	xrange      jsregexp.JsRegex
	star        jsregexp.JsRegex
	gte0        jsregexp.JsRegex
	build       jsregexp.JsRegex
	build_strip jsregexp.JsRegex
}

fn vsem_safe_regex(s string) !jsregexp.JsRegex {
	return jsregexp.js_regex_new(vsem_safe(s), '')
}

fn vsem_re() !VsemRe {
	ni := '0|[1-9]\\d*'
	nni := '\\d*[a-zA-Z-]${vsem_ldn}*'
	main_version := '(${ni})\\.(${ni})\\.(${ni})'
	pri := '(?:${nni}|${ni})'
	prerelease := '(?:-(${pri}(?:\\.${pri})*))'
	bi := '${vsem_ldn}+'
	build := '(?:\\+(${bi}(?:\\.${bi})*))'
	full_plain := 'v?${main_version}${prerelease}?${build}?'
	gtlt := '((?:<|>)?=?)'
	xri := '${ni}|x|X|\\*'
	xrange_plain := '[v=\\s]*(${xri})(?:\\.(${xri})(?:\\.(${xri})(?:${prerelease})?${build}?)?)?'
	lone_tilde := '(?:~>?)'
	lone_caret := '(?:\\^)'
	return VsemRe{
		full:        vsem_safe_regex('^${full_plain}$')!
		comparator:  vsem_safe_regex('^${gtlt}\\s*(${full_plain})$|^$')!
		hyphen:      vsem_safe_regex('^\\s*(${xrange_plain})\\s+-\\s+(${xrange_plain})\\s*$')!
		tilde_trim:  vsem_safe_regex('(\\s*)${lone_tilde}\\s+')!
		caret_trim:  vsem_safe_regex('(\\s*)${lone_caret}\\s+')!
		tilde:       vsem_safe_regex('^${lone_tilde}${xrange_plain}$')!
		caret:       vsem_safe_regex('^${lone_caret}${xrange_plain}$')!
		xrange:      vsem_safe_regex('^${gtlt}\\s*${xrange_plain}$')!
		star:        vsem_safe_regex('(<|>)?=?\\s*\\*')!
		gte0:        vsem_safe_regex('^\\s*>=\\s*0\\.0\\.0\\s*$')!
		build:       vsem_safe_regex(build)!
		build_strip: jsregexp.js_regex_new(build, '')!
	}
}

// vsem_groups are the match and the groups of an exec ('' for a group that did not take part,
// as undefined is wherever it is read).
fn vsem_groups(units []u16, start int, end int, slots []int) []string {
	mut groups := [utf16_to_string(units[start..end])]
	for g := 2; g + 1 < slots.len; g += 2 {
		groups << if slots[g] < 0 { '' } else { utf16_to_string(units[slots[g]..slots[g + 1]]) }
	}
	return groups
}

// vsem_replace is `text.replace(re, fn)` (every match with `global`): `with` gets the groups.
fn vsem_replace(re &jsregexp.JsRegex, text string, global bool, with fn ([]string) string) string {
	units := utf16_units(text)
	mut out := []u16{}
	mut from := 0
	mut copied := 0
	for from <= units.len {
		found, start, end, slots := re.exec(units, from) or { break }
		if !found {
			break
		}
		out << units[copied..start]
		out << utf16_units(with(vsem_groups(units, start, end, slots)))
		copied = end
		if !global {
			break
		}
		from = if end == start { end + 1 } else { end }
	}
	if copied < units.len {
		out << units[copied..]
	}
	return utf16_to_string(out)
}

fn vsem_remove(re &jsregexp.JsRegex, text string, global bool) string {
	return vsem_replace(re, text, global, fn (_ []string) string {
		return ''
	})
}

// vsem_match is `text.match(re)` for a regular expression without `g`: its groups.
fn vsem_match(re &jsregexp.JsRegex, text string) ?[]string {
	units := utf16_units(text)
	found, start, end, slots := re.exec(units, 0) or { return none }
	if !found {
		return none
	}
	return vsem_groups(units, start, end, slots)
}

// vsem_split_space is `text.split(/\s+/)`.
fn vsem_split_space(text string) []string {
	mut out := []string{}
	mut current := []rune{}
	mut in_space := false
	for r in text.runes() {
		if is_js_space(r) {
			if !in_space {
				out << current.string()
				current = []rune{}
				in_space = true
			}
		} else {
			current << r
			in_space = false
		}
	}
	out << current.string()
	return out
}

// vsem_is_x is isX: a missing, `x`, `X` or `*` component.
fn vsem_is_x(id string) bool {
	return id == '' || id == 'x' || id == 'X' || id == '*'
}

// vsem_inc is `+id + 1` printed. A component too long for an exact integer gives one that
// SemVer rejects (larger than MAX_SAFE_INTEGER), as JavaScript's rounded number is.
fn vsem_inc(id string) string {
	if id.len > 18 {
		return id + '0'
	}
	return (id.u64() + 1).str()
}

// VsemId is an identifier of a prerelease: a number, or a text.
struct VsemId {
	is_num bool
	num    i64
	text   string
}

// VsemVersion is a SemVer.
struct VsemVersion {
	major      i64
	minor      i64
	patch      i64
	prerelease []VsemId
	version    string
}

fn vsem_component(s string, what string) !i64 {
	if s.len > 16 || s.i64() > vsem_max_safe_integer {
		return error('Invalid ${what} version')
	}
	return s.i64()
}

fn vsem_numeric(s string) bool {
	return s.len > 0 && s.bytes().all(it.is_digit())
}

// version is `new SemVer(text)`.
fn (r &VsemRe) version(text string) !VsemVersion {
	if utf16_units(text).len > vsem_max_length {
		return error('version is longer than ${vsem_max_length} characters')
	}
	m := vsem_match(&r.full, js_trim(text)) or { return error('Invalid Version: ${text}') }
	major := vsem_component(m[1], 'major')!
	minor := vsem_component(m[2], 'minor')!
	patch := vsem_component(m[3], 'patch')!
	mut prerelease := []VsemId{}
	if m[4] != '' {
		for id in m[4].split('.') {
			if vsem_numeric(id) && id.len <= 16 && id.i64() < vsem_max_safe_integer {
				prerelease << VsemId{
					is_num: true
					num:    id.i64()
					text:   id.i64().str()
				}
			} else {
				prerelease << VsemId{
					text: id
				}
			}
		}
	}
	mut version := '${major}.${minor}.${patch}'
	if prerelease.len > 0 {
		version += '-' + prerelease.map(it.text).join('.')
	}
	return VsemVersion{
		major:      major
		minor:      minor
		patch:      patch
		prerelease: prerelease
		version:    version
	}
}

fn vsem_sign(x f64, y f64) int {
	return if x == y {
		0
	} else if x < y {
		-1
	} else {
		1
	}
}

// vsem_compare_ids is compareIdentifiers.
fn vsem_compare_ids(a VsemId, b VsemId) int {
	if a.is_num && b.is_num {
		return vsem_sign(f64(a.num), f64(b.num))
	}
	anum := vsem_numeric(a.text)
	bnum := vsem_numeric(b.text)
	if anum && bnum {
		return vsem_sign(a.text.f64(), b.text.f64())
	}
	if a.text == b.text {
		return 0
	}
	if anum && !bnum {
		return -1
	}
	if bnum && !anum {
		return 1
	}
	return if utf16_less(a.text, b.text) { -1 } else { 1 }
}

// vsem_compare is SemVer.compare.
fn vsem_compare(a VsemVersion, b VsemVersion) int {
	if a.version == b.version {
		return 0
	}
	for pair in [[a.major, b.major], [a.minor, b.minor], [a.patch, b.patch]] {
		if pair[0] < pair[1] {
			return -1
		}
		if pair[0] > pair[1] {
			return 1
		}
	}
	if a.prerelease.len > 0 && b.prerelease.len == 0 {
		return -1
	}
	if a.prerelease.len == 0 && b.prerelease.len > 0 {
		return 1
	}
	mut i := 0
	for {
		if i >= a.prerelease.len && i >= b.prerelease.len {
			return 0
		}
		if i >= b.prerelease.len {
			return 1
		}
		if i >= a.prerelease.len {
			return -1
		}
		x := a.prerelease[i]
		y := b.prerelease[i]
		if x.is_num != y.is_num || x.text != y.text {
			return vsem_compare_ids(x, y)
		}
		i++
	}
	return 0
}

// VsemComp is a Comparator: `any` is the ANY semver (value '').
struct VsemComp {
	operator string
	any      bool
	semver   VsemVersion
	value    string
}

// comparator is `new Comparator(text)`.
fn (r &VsemRe) comparator(text string) !VsemComp {
	comp := vsem_split_space(js_trim(text)).join(' ')
	m := vsem_match(&r.comparator, comp) or { return error('Invalid comparator: ${comp}') }
	operator := if m[1] == '=' { '' } else { m[1] }
	if m[2] == '' {
		return VsemComp{
			operator: operator
			any:      true
		}
	}
	semver := r.version(m[2])!
	return VsemComp{
		operator: operator
		semver:   semver
		value:    operator + semver.version
	}
}

// test is Comparator.test.
fn (c &VsemComp) test(v VsemVersion) bool {
	if c.any {
		return true
	}
	x := vsem_compare(v, c.semver)
	return match c.operator {
		'>' { x > 0 }
		'>=' { x >= 0 }
		'<' { x < 0 }
		'<=' { x <= 0 }
		else { x == 0 }
	}
}

fn (c &VsemComp) is_gt() bool {
	return c.operator == '>' || c.operator == '>='
}

fn (c &VsemComp) is_lt() bool {
	return c.operator == '<' || c.operator == '<='
}

// VsemSimple is a comparator set of a Range. `key` is the key of parseRange's memo (the same
// array, `===`, for the same text), '' for a null set, which is not memoized.
struct VsemSimple {
	comps []VsemComp
	key   string
}

// VsemRange is a Range: `raw` is the text getSemverRange's cache is keyed by.
struct VsemRange {
	raw string
	set []VsemSimple
}

// range is `new Range(text)` without options.
fn (r &VsemRe) range(text string) !VsemRange {
	raw := vsem_split_space(js_trim(text)).join(' ')
	mut set := []VsemSimple{}
	for part in raw.split('||') {
		simple := r.parse_range(js_trim(part))!
		if simple.comps.len > 0 {
			set << simple
		}
	}
	if set.len == 0 {
		return error('Invalid SemVer Range: ${raw}')
	}
	if set.len > 1 {
		first := set[0]
		set = set.filter(it.comps[0].value != '<0.0.0-0')
		if set.len == 0 {
			set = [first]
		} else if set.len > 1 {
			for s in set {
				if s.comps.len == 1 && s.comps[0].value == '' {
					set = [s]
					break
				}
			}
		}
	}
	return VsemRange{
		raw: text
		set: set
	}
}

// parse_range is Range.parseRange.
fn (r &VsemRe) parse_range(text string) !VsemSimple {
	mut range := vsem_remove(&r.build_strip, text, true)
	key := range
	range = vsem_replace(&r.hyphen, range, false, vsem_hyphen_replace)
	range = vsem_trim_comparator_whitespace(range)
	range = vsem_replace(&r.tilde_trim, range, true, fn (m []string) string {
		return m[1] + '~'
	})
	range = vsem_replace(&r.caret_trim, range, true, fn (m []string) string {
		return m[1] + '^'
	})
	parsed := range.split(' ').map(r.parse_comparator(it)).join(' ')
	mut comps := []VsemComp{}
	for comp in vsem_split_space(parsed) {
		comps << r.comparator(vsem_remove(&r.gte0, js_trim(comp), false))!
	}
	mut by_value := map[string]VsemComp{}
	for c in comps {
		if c.value == '<0.0.0-0' {
			return VsemSimple{
				comps: [c]
			}
		}
		by_value[c.value] = c
	}
	if by_value.len > 1 && '' in by_value {
		by_value.delete('')
	}
	return VsemSimple{
		comps: by_value.values()
		key:   key
	}
}

// parse_comparator is parseComparator: carets, tildes, x-ranges and stars made comparators.
fn (r &VsemRe) parse_comparator(text string) string {
	mut comp := vsem_remove(&r.build, text, false)
	comp = vsem_split_space(js_trim(comp)).map(vsem_replace(&r.caret, it, false, vsem_caret)).join(' ')
	comp = vsem_split_space(js_trim(comp)).map(vsem_replace(&r.tilde, it, false, vsem_tilde)).join(' ')
	comp = vsem_split_space(comp).map(r.replace_xrange(it)).join(' ')
	return vsem_remove(&r.star, js_trim(comp), false)
}

// vsem_tilde is replaceTilde's callback.
fn vsem_tilde(g []string) string {
	big, minor, patch, pr := g[1], g[2], g[3], g[4]
	return if vsem_is_x(big) {
		''
	} else if vsem_is_x(minor) {
		'>=${big}.0.0 <${vsem_inc(big)}.0.0-0'
	} else if vsem_is_x(patch) {
		'>=${big}.${minor}.0 <${big}.${vsem_inc(minor)}.0-0'
	} else if pr != '' {
		'>=${big}.${minor}.${patch}-${pr} <${big}.${vsem_inc(minor)}.0-0'
	} else {
		'>=${big}.${minor}.${patch} <${big}.${vsem_inc(minor)}.0-0'
	}
}

// vsem_caret is replaceCaret's callback.
fn vsem_caret(g []string) string {
	big, minor, patch, pr := g[1], g[2], g[3], g[4]
	if vsem_is_x(big) {
		return ''
	}
	if vsem_is_x(minor) {
		return '>=${big}.0.0 <${vsem_inc(big)}.0.0-0'
	}
	if vsem_is_x(patch) {
		if big == '0' {
			return '>=${big}.${minor}.0 <${big}.${vsem_inc(minor)}.0-0'
		}
		return '>=${big}.${minor}.0 <${vsem_inc(big)}.0.0-0'
	}
	from := if pr != '' { '>=${big}.${minor}.${patch}-${pr}' } else { '>=${big}.${minor}.${patch}' }
	if big == '0' {
		if minor == '0' {
			return '${from} <${big}.${minor}.${vsem_inc(patch)}-0'
		}
		return '${from} <${big}.${vsem_inc(minor)}.0-0'
	}
	return '${from} <${vsem_inc(big)}.0.0-0'
}

// replace_xrange is replaceXRange.
fn (r &VsemRe) replace_xrange(text string) string {
	comp := js_trim(text)
	return vsem_replace(&r.xrange, comp, false, fn [comp] (g []string) string {
		mut gtlt, mut big, mut minor, mut patch := g[1], g[2], g[3], g[4]
		if (vsem_is_x(big) && !vsem_is_x(minor))
			|| (vsem_is_x(minor) && patch != '' && !vsem_is_x(patch)) {
			return comp
		}
		xbig := vsem_is_x(big)
		xminor := xbig || vsem_is_x(minor)
		any_x := xminor || vsem_is_x(patch)
		if gtlt == '=' && any_x {
			gtlt = ''
		}
		if xbig {
			return if gtlt == '>' || gtlt == '<' { '<0.0.0-0' } else { '*' }
		}
		if gtlt != '' && any_x {
			if xminor {
				minor = '0'
			}
			patch = '0'
			if gtlt == '>' {
				gtlt = '>='
				if xminor {
					big = vsem_inc(big)
					minor = '0'
				} else {
					minor = vsem_inc(minor)
				}
			} else if gtlt == '<=' {
				gtlt = '<'
				if xminor {
					big = vsem_inc(big)
				} else {
					minor = vsem_inc(minor)
				}
			}
			pr := if gtlt == '<' { '-0' } else { '' }
			return '${gtlt}${big}.${minor}.${patch}${pr}'
		}
		if xminor {
			return '>=${big}.0.0 <${vsem_inc(big)}.0.0-0'
		}
		if any_x {
			return '>=${big}.${minor}.0 <${big}.${vsem_inc(minor)}.0-0'
		}
		return g[0]
	})
}

// vsem_hyphen_replace is hyphenReplace(false)'s callback.
fn vsem_hyphen_replace(g []string) string {
	mut from, fbig, fminor, fpatch := g[1], g[2], g[3], g[4]
	mut to, tbig, tminor, tpatch, tpr := g[7], g[8], g[9], g[10], g[11]
	if vsem_is_x(fbig) {
		from = ''
	} else if vsem_is_x(fminor) {
		from = '>=${fbig}.0.0'
	} else if vsem_is_x(fpatch) {
		from = '>=${fbig}.${fminor}.0'
	} else {
		from = '>=${from}'
	}
	if vsem_is_x(tbig) {
		to = ''
	} else if vsem_is_x(tminor) {
		to = '<${vsem_inc(tbig)}.0.0-0'
	} else if vsem_is_x(tpatch) {
		to = '<${tbig}.${vsem_inc(tminor)}.0-0'
	} else if tpr != '' {
		to = '<=${tbig}.${tminor}.${tpatch}-${tpr}'
	} else {
		to = '<=${to}'
	}
	return js_trim('${from} ${to}')
}

// VsemScan reads a range text for trimComparatorWhitespace (positions past the end read nothing).
struct VsemScan {
	s []rune
}

fn (v &VsemScan) at(i int) rune {
	return if i >= 0 && i < v.s.len { v.s[i] } else { rune(-1) }
}

fn (v &VsemScan) ws(i int) bool {
	r := v.at(i)
	return r >= 0 && is_js_space(r)
}

fn (v &VsemScan) digit(i int) bool {
	r := v.at(i)
	return r >= `0` && r <= `9`
}

fn (v &VsemScan) letter(i int) bool {
	r := v.at(i)
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`)
}

fn (v &VsemScan) ident(i int) bool {
	return v.digit(i) || v.letter(i) || v.at(i) == `-`
}

fn (v &VsemScan) prefix(i int) bool {
	return v.at(i) == `v` || v.at(i) == `=` || v.ws(i)
}

fn (v &VsemScan) version_start(i int) bool {
	return v.digit(i) || v.at(i) in [`x`, `X`, `*`]
}

// digits_end is findDigitsEndIndex (its cache only saves time).
fn (v &VsemScan) digits_end(start int, limit int) int {
	if !v.digit(start) {
		return start
	}
	mut end := start + 1
	for v.digit(end) {
		end++
	}
	return if start + limit < end { start + limit } else { end }
}

fn (v &VsemScan) number_end(start int, loose bool) int {
	if !loose && v.at(start) == `0` {
		return start + 1
	}
	return v.digits_end(start, if loose { vsem_max_length } else { vsem_max_length + 1 })
}

fn (v &VsemScan) pre_ident_end(start int, loose bool) int {
	d := v.digits_end(start, vsem_max_length)
	if v.letter(d) || v.at(d) == `-` {
		mut end := d + 1
		limit := end + vsem_max_length - 6
		for end < limit && v.ident(end) {
			end++
		}
		return end
	}
	return v.number_end(start, loose)
}

fn (v &VsemScan) pre_end(start int, loose bool) int {
	hyphen := v.at(start) == `-`
	if !loose && !hyphen {
		return start
	}
	ident_start := start + if hyphen { 1 } else { 0 }
	mut end := v.pre_ident_end(ident_start, loose)
	if end == ident_start {
		if !loose || !hyphen {
			return start
		}
		end = v.pre_ident_end(start, loose)
	}
	for v.at(end) == `.` {
		next := v.pre_ident_end(end + 1, loose)
		if next == end + 1 {
			break
		}
		end = next
	}
	return end
}

fn (v &VsemScan) build_ident_end(start int) int {
	mut end := start
	for end - start < vsem_max_length - 6 && v.ident(end) {
		end++
	}
	return end
}

fn (v &VsemScan) build_end(start int) int {
	if v.at(start) != `+` {
		return start
	}
	mut end := v.build_ident_end(start + 1)
	if end == start + 1 {
		return start
	}
	for v.at(end) == `.` {
		next := v.build_ident_end(end + 1)
		if next == end + 1 {
			break
		}
		end = next
	}
	return end
}

fn (v &VsemScan) loose_full_end(start int) int {
	mut end := start
	for component in 0 .. 3 {
		next := v.number_end(end, true)
		if next == end {
			return start
		}
		end = next
		if component < 2 {
			if v.at(end) != `.` {
				return start
			}
			end++
		}
	}
	return v.build_end(v.pre_end(end, true))
}

fn (v &VsemScan) partial_component_end(start int) int {
	if v.digit(start) {
		return v.number_end(start, false)
	}
	return if v.version_start(start) { start + 1 } else { start }
}

fn (v &VsemScan) partial_end(start int) int {
	mut end := v.partial_component_end(start)
	for _ in 0 .. 2 {
		if v.at(end) != `.` {
			return end
		}
		next := v.partial_component_end(end + 1)
		if next == end + 1 {
			return end
		}
		end = next
	}
	return v.build_end(v.pre_end(end, false))
}

// vsem_trim_comparator_whitespace is trimComparatorWhitespace: `> 1.2.3` made `>1.2.3`.
fn vsem_trim_comparator_whitespace(text string) string {
	v := VsemScan{
		s: text.runes()
	}
	s := v.s
	mut result := []rune{}
	mut copy_from := 0
	mut cursor := 0
	for cursor < s.len {
		match_start := cursor
		if s[cursor] == `<` || s[cursor] == `>` {
			cursor++
		} else if !v.prefix(cursor) && !v.version_start(cursor) {
			cursor++
			continue
		}
		for cursor < s.len && v.prefix(cursor) {
			cursor++
		}
		if !v.version_start(cursor) {
			continue
		}
		mut position := match_start
		if v.ws(position) {
			position++
		}
		if v.at(position) == `<` || v.at(position) == `>` {
			position++
		}
		if v.at(position) == `=` {
			position++
		}
		if v.ws(position) {
			result << s[copy_from..position]
			copy_from = position + 1
		}
		full := v.loose_full_end(cursor)
		cursor = if full != cursor { full } else { v.partial_end(cursor) }
	}
	if copy_from < s.len {
		result << s[copy_from..]
	}
	return result.string()
}

// test is Range.test.
fn (r &VsemRange) test(v VsemVersion) bool {
	for s in r.set {
		if vsem_test_set(s.comps, v) {
			return true
		}
	}
	return false
}

fn vsem_test_set(set []VsemComp, v VsemVersion) bool {
	for c in set {
		if !c.test(v) {
			return false
		}
	}
	if v.prerelease.len > 0 {
		for c in set {
			if c.any {
				continue
			}
			if c.semver.prerelease.len > 0 && c.semver.major == v.major
				&& c.semver.minor == v.minor && c.semver.patch == v.patch {
				return true
			}
		}
		return false
	}
	return true
}

// satisfies is `satisfies(version, range)` (false when the range is invalid).
fn (r &VsemRe) satisfies(v VsemVersion, range string) bool {
	parsed := r.range(range) or { return false }
	return parsed.test(v)
}

// subset is `subset(sub, dom)` of two Ranges (the same object when their texts are the same).
fn (r &VsemRe) subset(sub VsemRange, dom VsemRange) !bool {
	if sub.raw == dom.raw {
		return true
	}
	mut saw_non_null := false
	outer: for simple_sub in sub.set {
		for simple_dom in dom.set {
			is_sub := r.simple_subset(simple_sub, simple_dom)!
			saw_non_null = saw_non_null || is_sub != .null
			if is_sub == .yes {
				continue outer
			}
		}
		if saw_non_null {
			return false
		}
	}
	return true
}

enum VsemSubset {
	no
	yes
	null // a null set
}

// vsem_higher_gt is higherGT: whether it picks `b` (always when there is no `a`).
fn vsem_higher_gt(a ?VsemComp, b VsemComp) bool {
	x := a or { return true }
	comp := vsem_compare(x.semver, b.semver)
	return comp < 0 || (comp == 0 && b.operator == '>' && x.operator == '>=')
}

// vsem_lower_lt is lowerLT: whether it picks `b`.
fn vsem_lower_lt(a ?VsemComp, b VsemComp) bool {
	x := a or { return true }
	comp := vsem_compare(x.semver, b.semver)
	return comp > 0 || (comp == 0 && b.operator == '<' && x.operator == '<=')
}

fn vsem_same_tuple(c VsemComp, v VsemVersion) bool {
	return !c.any && c.semver.prerelease.len > 0 && c.semver.major == v.major
		&& c.semver.minor == v.minor && c.semver.patch == v.patch
}

// simple_subset is simpleSubset.
fn (r &VsemRe) simple_subset(simple_sub VsemSimple, simple_dom VsemSimple) !VsemSubset {
	if simple_sub.key != '' && simple_sub.key == simple_dom.key {
		return .yes
	}
	mut sub := simple_sub.comps.clone()
	mut dom := simple_dom.comps.clone()
	if sub.len == 1 && sub[0].any {
		if dom.len == 1 && dom[0].any {
			return .yes
		}
		sub = [r.comparator('>=0.0.0')!]
	}
	if dom.len == 1 && dom[0].any {
		dom = [r.comparator('>=0.0.0')!]
	}
	// eqSet is a Set of SemVer objects; parseRange keeps one comparator per value, so one object
	// per version.
	mut eq_set := []VsemVersion{}
	mut gt := ?VsemComp(none)
	mut lt := ?VsemComp(none)
	for c in sub {
		if c.is_gt() {
			if vsem_higher_gt(gt, c) {
				gt = c
			}
		} else if c.is_lt() {
			if vsem_lower_lt(lt, c) {
				lt = c
			}
		} else if !eq_set.any(it.version == c.semver.version) {
			eq_set << c.semver
		}
	}
	if eq_set.len > 1 {
		return .null
	}
	// gtltComp is undefined (not 0) without both bounds.
	mut gtlt_comp := 1
	if g := gt {
		if l := lt {
			gtlt_comp = vsem_compare(g.semver, l.semver)
			if gtlt_comp > 0 {
				return .null
			} else if gtlt_comp == 0 && (g.operator != '>=' || l.operator != '<=') {
				return .null
			}
		}
	}
	for eq in eq_set {
		if g := gt {
			if !r.satisfies(eq, g.value) {
				return .null
			}
		}
		if l := lt {
			if !r.satisfies(eq, l.value) {
				return .null
			}
		}
		for c in dom {
			if !r.satisfies(eq, c.value) {
				return .no
			}
		}
		return .yes
	}
	mut has_dom_lt := false
	mut has_dom_gt := false
	mut need_lt_pre := ?VsemVersion(none)
	mut need_gt_pre := ?VsemVersion(none)
	if l := lt {
		p := l.semver.prerelease
		// <1.2.3-0 is the same as <1.2.3.
		if p.len > 0 && !(p.len == 1 && l.operator == '<' && p[0].is_num && p[0].num == 0) {
			need_lt_pre = l.semver
		}
	}
	if g := gt {
		if g.semver.prerelease.len > 0 {
			need_gt_pre = g.semver
		}
	}
	for c in dom {
		has_dom_gt = has_dom_gt || c.is_gt()
		has_dom_lt = has_dom_lt || c.is_lt()
		if g := gt {
			if need := need_gt_pre {
				if vsem_same_tuple(c, need) {
					need_gt_pre = none
				}
			}
			if c.is_gt() {
				if vsem_higher_gt(g, c) {
					return .no
				}
			} else if g.operator == '>=' && !c.test(g.semver) {
				return .no
			}
		}
		if l := lt {
			if need := need_lt_pre {
				if vsem_same_tuple(c, need) {
					need_lt_pre = none
				}
			}
			if c.is_lt() {
				if vsem_lower_lt(l, c) {
					return .no
				}
			} else if l.operator == '<=' && !c.test(l.semver) {
				return .no
			}
		}
		if c.operator == '' && (lt != none || gt != none) && gtlt_comp != 0 {
			return .no
		}
	}
	if gt != none && has_dom_lt && lt == none && gtlt_comp != 0 {
		return .no
	}
	if lt != none && has_dom_gt && gt == none && gtlt_comp != 0 {
		return .no
	}
	if need_gt_pre != none || need_lt_pre != none {
		return .no
	}
	return .yes
}
