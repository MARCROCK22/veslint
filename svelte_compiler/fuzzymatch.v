module svelte_compiler

import math

// fuzzymatch is phases/1-parse/utils/fuzzymatch.js (a FuzzySet of 2- and 3-grams): the name of
// `names` closest to `name`, or '' when none scores above 0.7.
fn fuzzymatch(name string, names []string) string {
	if names.len == 0 {
		return ''
	}
	mut set := new_fuzzy_set(names)
	best, value := set.get(name) or { return '' }
	return if best > 0.7 { value } else { '' }
}

struct FuzzyItem {
	normal f64
	value  string
}

struct FuzzySet {
mut:
	exact_set  map[string]string
	match_dict map[string][][]int
	items      map[int][]FuzzyItem
}

fn new_fuzzy_set(arr []string) FuzzySet {
	mut s := FuzzySet{}
	s.items[2] = []FuzzyItem{}
	s.items[3] = []FuzzyItem{}
	for v in arr {
		s.add(v)
	}
	return s
}

fn (mut s FuzzySet) add(value string) {
	if value.to_lower() in s.exact_set {
		return
	}
	for gram_size in 2 .. 4 {
		s.add_size(value, gram_size)
	}
}

fn (mut s FuzzySet) add_size(value string, gram_size int) {
	normalized := value.to_lower()
	mut items := s.items[gram_size] or { []FuzzyItem{} }
	index := items.len
	grams, counts := gram_counter(normalized, gram_size)
	mut sum := 0
	for k, gram in grams {
		c := counts[k]
		sum += c * c
		if gram in s.match_dict {
			s.match_dict[gram] << [index, c]
		} else {
			s.match_dict[gram] = [[index, c]]
		}
	}
	items << FuzzyItem{
		normal: math.sqrt(f64(sum))
		value:  normalized
	}
	s.items[gram_size] = items
	s.exact_set[normalized] = value
}

fn (s &FuzzySet) get(value string) ?(f64, string) {
	normalized := value.to_lower()
	if result := s.exact_set[normalized] {
		if result != '' {
			return 1.0, result
		}
	}
	for gram_size := 3; gram_size >= 2; gram_size-- {
		results := s.get_size(value, gram_size)
		if results.len > 0 {
			return results[0].score, results[0].value
		}
	}
	return none
}

struct FuzzyResult {
	score f64
	value string
}

fn (s &FuzzySet) get_size(value string, gram_size int) []FuzzyResult {
	normalized := value.to_lower()
	mut matches := map[int]int{}
	grams, counts := gram_counter(normalized, gram_size)
	items := s.items[gram_size] or { []FuzzyItem{} }
	mut sum := 0
	for k, gram in grams {
		c := counts[k]
		sum += c * c
		if entries := s.match_dict[gram] {
			for e in entries {
				matches[e[0]] = (matches[e[0]] or { 0 }) + c * e[1]
			}
		}
	}
	normal := math.sqrt(f64(sum))
	// `for (const match_index in matches)`: integer keys, in ascending order.
	mut keys := matches.keys()
	keys.sort()
	mut results := []FuzzyResult{}
	for idx in keys {
		results << FuzzyResult{
			score: f64(matches[idx]) / (normal * items[idx].normal)
			value: items[idx].value
		}
	}
	stable_sort_desc(mut results)
	mut next := []FuzzyResult{}
	for i in 0 .. math.min(50, results.len) {
		next << FuzzyResult{
			score: fuzzy_distance(results[i].value, normalized)
			value: results[i].value
		}
	}
	stable_sort_desc(mut next)
	mut out := []FuzzyResult{}
	for r in next {
		if r.score == next[0].score {
			out << FuzzyResult{
				score: r.score
				value: s.exact_set[r.value] or { '' }
			}
		}
	}
	return out
}

// stable_sort_desc sorts by descending score keeping the order of equal scores (Array#sort is
// stable).
fn stable_sort_desc(mut a []FuzzyResult) {
	for i in 1 .. a.len {
		x := a[i]
		mut j := i - 1
		for j >= 0 && a[j].score < x.score {
			a[j + 1] = a[j]
			j--
		}
		a[j + 1] = x
	}
}

// gram_counter counts the grams of `-value-` (the first run of characters other than word
// characters, `,` and space removed: the regex has no `g` flag), in first-seen order — except
// that integer-like grams come first in ascending order, as JavaScript orders object keys.
fn gram_counter(value string, gram_size int) ([]string, []int) {
	simplified := '-' + remove_first_non_word(value) + '-'
	mut grams := []string{}
	mut counts := []int{}
	mut index := map[string]int{}
	units := simplified.runes()
	for i := 0; i < units.len - gram_size + 1; i++ {
		g := units[i..i + gram_size].string()
		if k := index[g] {
			counts[k]++
		} else {
			index[g] = grams.len
			grams << g
			counts << 1
		}
	}
	mut int_keys := []int{}
	for k, g in grams {
		if is_array_index(g) {
			int_keys << k
		}
	}
	if int_keys.len == 0 {
		return grams, counts
	}
	int_keys.sort_with_compare(fn [grams] (a &int, b &int) int {
		return grams[*a].int() - grams[*b].int()
	})
	mut og := []string{}
	mut oc := []int{}
	for k in int_keys {
		og << grams[k]
		oc << counts[k]
	}
	for k, g in grams {
		if !is_array_index(g) {
			og << g
			oc << counts[k]
		}
	}
	return og, oc
}

fn is_array_index(s string) bool {
	if s.len == 0 || (s.len > 1 && s[0] == `0`) {
		return false
	}
	for c in s {
		if c < `0` || c > `9` {
			return false
		}
	}
	return true
}

fn is_word_or_comma_space(r rune) bool {
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`) || r == `_`
		|| r == `,` || r == ` `
}

fn remove_first_non_word(s string) string {
	rs := s.runes()
	mut i := 0
	for i < rs.len && is_word_or_comma_space(rs[i]) {
		i++
	}
	if i == rs.len {
		return s
	}
	mut j := i
	for j < rs.len && !is_word_or_comma_space(rs[j]) {
		j++
	}
	return rs[..i].string() + rs[j..].string()
}

fn fuzzy_distance(a string, b string) f64 {
	ua := a.runes()
	ub := b.runes()
	d := levenshtein(ua, ub)
	return 1.0 - f64(d) / f64(math.max(ua.len, ub.len))
}

fn levenshtein(s1 []rune, s2 []rune) int {
	mut current := []int{len: s1.len + 1}
	mut prev := 0
	for i in 0 .. s2.len + 1 {
		for j in 0 .. s1.len + 1 {
			mut value := 0
			if i > 0 && j > 0 {
				if s1[j - 1] == s2[i - 1] {
					value = prev
				} else {
					value = math.min(math.min(current[j], current[j - 1]), prev) + 1
				}
			} else {
				value = i + j
			}
			prev = current[j]
			current[j] = value
		}
	}
	return current.last()
}
