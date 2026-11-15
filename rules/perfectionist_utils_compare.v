module rules

import collation
import json2
import jsregexp
import math

// The comparisons of eslint-plugin-perfectionist 5.13.0 (utils/compare/): the comparator of each
// sort type (`alphabetical`, `natural`, `line-length`, `custom`, `subgroup-order`, `unsorted`),
// the string formatter they share (build-string-formatter.ts), and natural-orderby 5.0.0's
// `compare`, which the `natural` type uses.
//
// localeCompare (of the `alphabetical` type, and of natural-orderby for the parts of a string that
// are not numbers when they are not ASCII) is Node's ICU collation for its default locale:
// collation.compare. The `locales` option is not read: a locale that collates like the root one
// (`en-US`, the default, `en`, `en-GB`…) gives the same order; others are a known limit.

// PfComparator is a comparator built from options (ComparatorByOptionsComputer); `unsorted` is
// unsortedComparator, which computeComparators drops.
struct PfComparator {
	unsorted bool
	cmp      fn (a &PfSortingNode, b &PfSortingNode) int = unsafe { nil }
}

// PfComparatorComputer ports ComparatorByOptionsComputer: the comparator of the options.
type PfComparatorComputer = fn (options map[string]json2.Any) PfComparator

// pf_default_comparator_computer ports defaultComparatorByOptionsComputer: the nodes by their
// name.
fn pf_default_comparator_computer(options map[string]json2.Any) PfComparator {
	return pf_string_comparator(options, false)
}

// pf_value_comparator_computer is the comparator of buildStringComparatorByOptionsComputer with
// the value of the nodes (name-or-value-comparator-by-options-computer.ts, `sortBy: 'value'`).
fn pf_value_comparator_computer(options map[string]json2.Any) PfComparator {
	return pf_string_comparator(options, true)
}

// pf_name_or_value_comparator_computer ports nameOrValueComparatorByOptionsComputer.
fn pf_name_or_value_comparator_computer(options map[string]json2.Any) PfComparator {
	return pf_string_comparator(options, pf_opt_string(options, 'sortBy') == 'value')
}

// pf_string_comparator ports buildStringComparatorByOptionsComputer: the comparator of the
// `type` of the options, on the name of the nodes (or their value, `by_value`).
fn pf_string_comparator(options map[string]json2.Any, by_value bool) PfComparator {
	settings := pf_compare_settings(options)
	match pf_opt_string(options, 'type') {
		'subgroup-order' {
			groups := options['groups'] or {
				return PfComparator{
					unsorted: true
				}
			}
			if groups !is []json2.Any {
				return PfComparator{
					unsorted: true
				}
			}
			list := groups.as_array()
			return PfComparator{
				cmp: fn [list, settings] (a &PfSortingNode, b &PfSortingNode) int {
					return pf_subgroup_order_compare(a, b, list, settings.order)
				}
			}
		}
		'alphabetical' {
			return PfComparator{
				cmp: fn [settings, by_value] (a &PfSortingNode, b &PfSortingNode) int {
					return pf_compare_alphabetically(pf_node_value(a, by_value), pf_node_value(b,
						by_value), settings)
				}
			}
		}
		'line-length' {
			return PfComparator{
				cmp: fn [settings] (a &PfSortingNode, b &PfSortingNode) int {
					return pf_ordered_value(a.size - b.size, settings.order)
				}
			}
		}
		'natural' {
			return PfComparator{
				cmp: fn [settings, by_value] (a &PfSortingNode, b &PfSortingNode) int {
					return pf_compare_naturally(pf_node_value(a, by_value), pf_node_value(b,
						by_value), settings)
				}
			}
		}
		'custom' {
			alphabet := pf_alphabet_index(settings.alphabet)
			return PfComparator{
				cmp: fn [settings, by_value, alphabet] (a &PfSortingNode, b &PfSortingNode) int {
					return pf_compare_by_custom_sort(pf_node_value(a, by_value), pf_node_value(b,
						by_value), settings, alphabet)
				}
			}
		}
		else {
			// 'unsorted'
			return PfComparator{
				unsorted: true
			}
		}
	}
}

fn pf_node_value(n &PfSortingNode, by_value bool) string {
	return if by_value { n.value } else { n.name }
}

// PfCompareSettings are the options the string comparisons read.
struct PfCompareSettings {
	order              string
	ignore_case        bool
	special_characters string
	alphabet           string
}

fn pf_compare_settings(options map[string]json2.Any) PfCompareSettings {
	return PfCompareSettings{
		order:              pf_opt_string(options, 'order')
		ignore_case:        pf_opt_truthy(options, 'ignoreCase')
		special_characters: pf_opt_string(options, 'specialCharacters')
		alphabet:           pf_opt_string(options, 'alphabet')
	}
}

// pf_compute_comparators ports computeComparators: the comparator of the options and the one of
// their fallbackSort over them, or none when the first one is unsortedComparator.
fn pf_compute_comparators(computer PfComparatorComputer, options map[string]json2.Any) []PfComparator {
	main := computer(options)
	if main.unsorted {
		return []PfComparator{}
	}
	mut fallback_options := options.clone()
	if fallback := options['fallbackSort'] {
		if fallback is map[string]json2.Any {
			for key, value in fallback.as_map() {
				fallback_options[key] = value
			}
		}
	}
	return [main, computer(fallback_options)]
}

// pf_ordered_value ports computeOrderedValue.
fn pf_ordered_value(value int, order string) int {
	return if order == 'desc' { -value } else { value }
}

// pf_sign ports convertBooleanToSign.
fn pf_sign(value bool) int {
	return if value { 1 } else { -1 }
}

// pf_subgroup_order_compare ports buildSubgroupOrderComparator: two nodes of the same subgroup
// (a list of groups in `groups`) by the place of their groups in it.
fn pf_subgroup_order_compare(a &PfSortingNode, b &PfSortingNode, groups []json2.Any, order string) int {
	index_a, subgroup_a := pf_subgroup_containing(a, groups) or { return 0 }
	index_b, _ := pf_subgroup_containing(b, groups) or { return 0 }
	if index_a != index_b {
		return 0
	}
	result := subgroup_a.index(a.group) - subgroup_a.index(b.group)
	return pf_ordered_value(result, order)
}

// pf_subgroup_containing ports computeSubgroupContainingNode: the index in `groups` of the list of
// groups (also of a group with overrides) that has the group of the node, and that list.
fn pf_subgroup_containing(node &PfSortingNode, groups []json2.Any) ?(int, []string) {
	for i, group in groups {
		if pf_is_newlines_between_option(group) {
			continue
		}
		if group is string {
			continue
		}
		if group is []json2.Any {
			names := pf_string_list(group)
			if node.group in names {
				return i, names
			}
			continue
		}
		if pf_is_group_with_overrides_option(group) {
			inner := group.as_map()['group'] or { json2.Any('') }
			if inner is []json2.Any {
				names := pf_string_list(inner)
				if node.group in names {
					return i, names
				}
			}
			continue
		}
	}
	return none
}

// pf_format_string ports buildStringFormatter: lower case with ignoreCase, the special characters
// removed or trimmed, and no white space.
fn pf_format_string(value string, ignore_case bool, special_characters string) string {
	mut units := utf16_units(value)
	if ignore_case {
		units = jsregexp.js_to_lower(units)
	}
	match special_characters {
		'remove' {
			units = pf_regex_replace(pf_re_special_characters, units, true, true, pf_remove_match)
		}
		'trim' {
			units = pf_regex_replace(pf_re_leading_special_characters, units, true, true,
				pf_remove_match)
		}
		else {}
	}
	units = pf_remove_js_spaces(units)
	return stv_units_string(units)
}

const pf_re_special_characters = jsregexp.js_regex_new('[^a-z\\u{C0}-\\u{24F}\\u{1E00}-\\u{1EFF}]+',
	'iu') or { panic(err) }
const pf_re_leading_special_characters = jsregexp.js_regex_new('^[^a-z\\u{C0}-\\u{24F}\\u{1E00}-\\u{1EFF}]+',
	'iu') or { panic(err) }

// pf_remove_js_spaces ports `.replaceAll(/\s/gu, '')`.
fn pf_remove_js_spaces(units []u16) []u16 {
	points := jsregexp.utf16_code_points(units)
	mut out := []u16{cap: units.len}
	for c in points {
		if !is_js_space(rune(c)) {
			jsregexp.append_utf16(mut out, c)
		}
	}
	return out
}

// pf_regex_replace ports `units.replace(regex, replacer)` (every match with `global`): each match
// is replaced by what `replacer` gives for it. `unicode` tells that the regular expression has the
// `u` flag (its indexes are of code points).
fn pf_regex_replace(re &jsregexp.JsRegex, units []u16, unicode bool, global bool, replacer fn ([]u16) []u16) []u16 {
	// The unit index of each code point index (and of the end).
	mut unit_of := []int{}
	if unicode {
		mut i := 0
		for i < units.len {
			unit_of << i
			if units[i] >= 0xd800 && units[i] <= 0xdbff && i + 1 < units.len
				&& units[i + 1] >= 0xdc00 && units[i + 1] <= 0xdfff {
				i += 2
			} else {
				i++
			}
		}
		unit_of << units.len
	}
	mut out := []u16{cap: units.len}
	mut last := 0
	mut from := 0
	limit := if unicode { unit_of.len - 1 } else { units.len }
	for from <= limit {
		found, start, end, _ := re.exec(units, from) or { break }
		if !found {
			break
		}
		unit_start := if unicode { unit_of[start] } else { start }
		unit_end := if unicode { unit_of[end] } else { end }
		out << units[last..unit_start]
		out << replacer(units[unit_start..unit_end])
		last = unit_end
		if !global {
			break
		}
		from = if end == start { end + 1 } else { end }
	}
	out << units[last..]
	return out
}

// pf_remove_match is the replacer of `.replace(regex, '')`.
fn pf_remove_match(_ []u16) []u16 {
	return []u16{}
}

// pf_compare_alphabetically ports compareAlphabetically.
fn pf_compare_alphabetically(a string, b string, settings PfCompareSettings) int {
	result := collation.compare(pf_format_string(a, settings.ignore_case, settings.special_characters),
		pf_format_string(b, settings.ignore_case, settings.special_characters))
	return pf_ordered_value(result, settings.order)
}

// pf_compare_naturally ports compareNaturally.
fn pf_compare_naturally(a string, b string, settings PfCompareSettings) int {
	result := pf_natural_compare(pf_format_string(a, settings.ignore_case, settings.special_characters),
		pf_format_string(b, settings.ignore_case, settings.special_characters))
	return pf_ordered_value(result, settings.order)
}

// pf_alphabet_index is the index of each character of a custom alphabet (`[...alphabet]`, by code
// point; a character given twice has its last index).
fn pf_alphabet_index(alphabet string) map[u32]int {
	mut out := map[u32]int{}
	for i, c in jsregexp.utf16_code_points(utf16_units(alphabet)) {
		out[c] = i
	}
	return out
}

// pf_compare_by_custom_sort ports compareByCustomSort: character by character (UTF-16 unit, as
// `value[i]` reads them), by their index in the alphabet (after every one of them when it has
// none), then by length.
fn pf_compare_by_custom_sort(a string, b string, settings PfCompareSettings, alphabet map[u32]int) int {
	a_value := utf16_units(pf_format_string(a, settings.ignore_case, settings.special_characters))
	b_value := utf16_units(pf_format_string(b, settings.ignore_case, settings.special_characters))
	min_length := math.min(a_value.len, b_value.len)
	for i in 0 .. min_length {
		index_of_a := pf_alphabet_unit_index(alphabet, a_value[i])
		index_of_b := pf_alphabet_unit_index(alphabet, b_value[i])
		if index_of_a != index_of_b {
			return pf_ordered_value(pf_sign(index_of_a > index_of_b), settings.order)
		}
	}
	if a_value.len == b_value.len {
		return 0
	}
	return pf_ordered_value(pf_sign(a_value.len > b_value.len), settings.order)
}

// pf_alphabet_unit_index: the index of a UTF-16 unit in the alphabet, or Infinity (max_int); a
// surrogate is never a character of the alphabet.
fn pf_alphabet_unit_index(alphabet map[u32]int, unit u16) int {
	if unit >= 0xd800 && unit <= 0xdfff {
		return max_int
	}
	return alphabet[u32(unit)] or { max_int }
}

// natural-orderby 5.0.0 (dist/index.js): `compare({ locale })(a, b)` for two strings.

const pf_re_numbers = jsregexp.js_regex_new('(^0x[\\da-fA-F]+$|^([+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?(?!\\.\\d+)(?=\\D|\\s|$))|\\d+)',
	'') or { panic(err) }
const pf_re_int_or_float = jsregexp.js_regex_new('^[+-]?(?:\\d+(?:\\.\\d*)?|\\.\\d+)(?:[eE][+-]?\\d+)?$',
	'') or { panic(err) }
const pf_re_date = jsregexp.js_regex_new('(^([\\w ]+,?[\\w ]+)?[\\w ]+,?[\\w ]+\\d+:\\d+(:\\d+)?[\\w ]?|^\\d{1,4}[/-]\\d{1,4}[/-]\\d{1,4}|^\\w+, \\w+ \\d+, \\d{4})',
	'') or { panic(err) }
const pf_re_leading_zero = jsregexp.js_regex_new('^0+[1-9]{1}[0-9]*$', '') or { panic(err) }

// PfNaturalChunk is a chunk map of natural-orderby: the number of a numeric chunk, and the chunk
// with its white space normalized.
struct PfNaturalChunk {
	parsed_number ?f64
	normalized    string
}

struct PfNaturalValue {
	parsed_number ?f64
	chunks        []PfNaturalChunk
	value         string
}

// pf_natural_compare ports baseCompare (ascending) for two strings.
fn pf_natural_compare(a string, b string) int {
	return pf_natural_compare_values(pf_natural_mapped(a), pf_natural_mapped(b))
}

// pf_natural_mapped ports getMappedValueRecord for a string.
fn pf_natural_mapped(value string) PfNaturalValue {
	string_value := pf_natural_stringify(value)
	parsed_number := pf_natural_numberify(string_value)
	text := if n := parsed_number {
		if n != 0 { js_number_to_string(n) } else { string_value }
	} else {
		string_value
	}
	return PfNaturalValue{
		parsed_number: parsed_number
		chunks:        pf_natural_chunk_maps(text)
		value:         value
	}
}

// pf_natural_stringify ports stringify for a string: lower case, without the white space around.
fn pf_natural_stringify(value string) string {
	return js_trim(stv_units_string(jsregexp.js_to_lower(utf16_units(value))))
}

// pf_natural_parse_number ports parseNumber: Number of the text without its `_`, unless NaN.
fn pf_natural_parse_number(value string) ?f64 {
	if value.len != 0 {
		parsed := js_string_to_number(value.replace('_', ''))
		if !math.is_nan(parsed) {
			return parsed
		}
	}
	return none
}

// pf_natural_numberify ports numberify: the number, or the date (Date.parse) of a text that looks
// like one.
fn pf_natural_numberify(value string) ?f64 {
	if n := pf_natural_parse_number(value) {
		return n
	}
	return pf_natural_parse_date(value)
}

// pf_natural_parse_date ports parseDate: Date.parse of a text RE_DATE matches. Of Date.parse,
// only the ISO dates `YYYY-MM-DD` (UTC, as V8 reads them) are ported; any other text is NaN here
// (V8's legacy parser reads more of them).
fn pf_natural_parse_date(value string) ?f64 {
	if !(pf_re_date.test(utf16_units(value)) or { false }) {
		return none
	}
	if value.len == 10 && value[4] == `-` && value[7] == `-` {
		digits := value[0..4] + value[5..7] + value[8..10]
		if digits.bytes().all(it.is_digit()) {
			year := value[0..4].int()
			month := value[5..7].int()
			day := value[8..10].int()
			if month >= 1 && month <= 12 && day >= 1 && day <= pf_days_in_month(year, month) {
				return f64(pf_days_from_civil(year, month, day)) * 86400000.0
			}
		}
	}
	return none
}

fn pf_days_in_month(year int, month int) int {
	return match month {
		2 {
			if (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 { 29 } else { 28 }
		}
		4, 6, 9, 11 {
			30
		}
		else {
			31
		}
	}
}

// pf_days_from_civil: the days from 1970-01-01 to the date (proleptic Gregorian).
fn pf_days_from_civil(year int, month int, day int) i64 {
	y := i64(if month <= 2 { year - 1 } else { year })
	era := (if y >= 0 { y } else { y - 399 }) / 400
	yoe := y - era * 400
	m := i64(month)
	doy := (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + i64(day) - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// pf_natural_chunk_maps ports createChunkMaps.
fn pf_natural_chunk_maps(value string) []PfNaturalChunk {
	chunks := pf_natural_chunks(value)
	mut out := []PfNaturalChunk{cap: chunks.len}
	for i, chunk in chunks {
		out << PfNaturalChunk{
			parsed_number: pf_natural_numeric_chunk(chunk, i, chunks)
			normalized:    pf_natural_alpha_chunk(chunk)
		}
	}
	return out
}

// pf_natural_chunks ports createChunks: the numbers apart from the rest.
fn pf_natural_chunks(value string) []string {
	// `value.replace(RE_NUMBERS, '\0$1\0')`: the first group is the whole match.
	units := pf_regex_replace(pf_re_numbers, utf16_units(value), false, true, fn (m []u16) []u16 {
		mut out := [u16(0)]
		out << m
		out << u16(0)
		return out
	})
	mut text := stv_units_string(units)
	if text.ends_with('\x00') {
		text = text[..text.len - 1]
	}
	if text.starts_with('\x00') {
		text = text[1..]
	}
	return text.split('\x00')
}

// pf_natural_alpha_chunk ports normalizeAlphaChunk: white space as one space, none around.
fn pf_natural_alpha_chunk(chunk string) string {
	mut runes := []rune{}
	mut in_space := false
	for r in chunk.runes() {
		if is_js_space(r) {
			if !in_space {
				runes << ` `
			}
			in_space = true
			continue
		}
		in_space = false
		runes << r
	}
	return js_trim(runes.string())
}

// pf_natural_numeric_chunk ports normalizeNumericChunk.
fn pf_natural_numeric_chunk(chunk string, index int, chunks []string) ?f64 {
	if pf_re_int_or_float.test(utf16_units(chunk)) or { false } {
		if !(pf_re_leading_zero.test(utf16_units(chunk)) or { false }) || index == 0
			|| chunks[index - 1] != '.' {
			n := pf_natural_parse_number(chunk) or { 0 }
			// `parseNumber(chunk) || 0`
			return if math.is_nan(n) { 0 } else { n }
		}
	}
	return none
}

// pf_natural_compare_values ports compareValues for two strings.
fn pf_natural_compare_values(a PfNaturalValue, b PfNaturalValue) int {
	if a.value == b.value {
		return 0
	}
	if na := a.parsed_number {
		if nb := b.parsed_number {
			return pf_compare_numbers(na, nb)
		}
	}
	return pf_natural_compare_chunks(a.chunks, b.chunks)
}

fn pf_compare_numbers(a f64, b f64) int {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}

// pf_utf16_compare ports stringCompare: `<` and `>` of JavaScript strings.
fn pf_utf16_compare(a string, b string) int {
	if a == b {
		return 0
	}
	return if utf16_less(a, b) { -1 } else { 1 }
}

// pf_natural_compare_chunks ports compareChunks.
fn pf_natural_compare_chunks(chunks_a []PfNaturalChunk, chunks_b []PfNaturalChunk) int {
	size := math.min(chunks_a.len, chunks_b.len)
	for i in 0 .. size {
		chunk_a := chunks_a[i]
		chunk_b := chunks_b[i]
		if chunk_a.normalized != chunk_b.normalized {
			if (chunk_a.normalized == '') != (chunk_b.normalized == '') {
				return if chunk_a.normalized == '' { -1 } else { 1 }
			}
			if na := chunk_a.parsed_number {
				if nb := chunk_b.parsed_number {
					result := pf_compare_numbers(na, nb)
					if result == 0 {
						return pf_utf16_compare(chunk_a.normalized, chunk_b.normalized)
					}
					return result
				}
				return -1
			}
			if _ := chunk_b.parsed_number {
				return 1
			}
			// RE_UNICODE_CHARACTERS: a character past U+0080 makes it localeCompare.
			both := chunk_a.normalized + chunk_b.normalized
			if utf16_units(both).any(it > 0x80) {
				return collation.compare(chunk_a.normalized, chunk_b.normalized)
			}
			return pf_utf16_compare(chunk_a.normalized, chunk_b.normalized)
		}
	}
	if chunks_a.len > size || chunks_b.len > size {
		return if chunks_a.len <= size { -1 } else { 1 }
	}
	return 0
}
