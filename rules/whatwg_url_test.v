module rules

import json2
import os

// The cases come from tools/gen_whatwg_url_cases.mjs: inputs and bases with the href of Node's
// `new URL(input, base)` (null when it throws), and whether isSafeToAddDotSlashToUrl of
// unicorn/relative-url-style holds (tests/whatwg_url_cases.json).

// wu_resolve is `new URL(input, base).href`.
fn wu_resolve(input string, base string) !string {
	parsed_base := wu_parse(base, false, WuUrl{})!
	return wu_href(wu_parse(input, true, parsed_base)!)
}

fn wu_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'whatwg_url_cases.json')) or {
		panic(err)
	}
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

// wu_test_mentions_domain tells whether a URL may hold a domain that needs UTS #46, which
// rules/whatwg_url.v does not port: a non-ASCII character (maybe percent-encoded) or `xn--`.
fn wu_test_mentions_domain(text string) bool {
	lower := text.to_lower()
	return text.bytes().any(it >= 0x80) || lower.contains('xn--') || lower.contains('%8')
		|| lower.contains('%9') || lower.contains('%a') || lower.contains('%b')
		|| lower.contains('%c') || lower.contains('%d') || lower.contains('%e')
		|| lower.contains('%f')
}

fn test_hrefs_match_node() {
	data := wu_cases()
	mut checked := 0
	mut unsupported := 0
	mut failures := []string{}
	for item in (data['hrefs'] or { panic('no hrefs') }).as_array() {
		values := item.as_array()
		input := values[0].str()
		has_base := values[1] !is json2.Null
		base := if has_base { values[1].str() } else { '' }
		want := if values[2] is json2.Null { '' } else { values[2].str() }
		mut got := ''
		if has_base {
			got = wu_resolve(input, base) or {
				if err.msg() == wu_unsupported {
					assert wu_test_mentions_domain(input) || wu_test_mentions_domain(base), '${input} ${base}'
					unsupported++
					continue
				}
				''
			}
		} else {
			parsed := wu_parse(input, false, WuUrl{}) or {
				if err.msg() == wu_unsupported {
					assert wu_test_mentions_domain(input), input
					unsupported++
					continue
				}
				WuUrl{}
			}
			got = if parsed.scheme == '' { '' } else { wu_href(parsed) }
		}
		checked++
		if got != want {
			failures << '${json2.encode(input)} against ${json2.encode(base)}: ${json2.encode(got)}, Node ${json2.encode(want)}'
		}
	}
	assert failures == []
	assert checked > 15000
	assert unsupported < 500
}

fn test_safety_matches_node() {
	data := wu_cases()
	mut failures := []string{}
	mut unknown := 0
	for item in (data['safe'] or { panic('no safe') }).as_array() {
		values := item.as_array()
		url := values[0].str()
		base := values[1].str()
		want := values[2].bool()
		got := wu_is_safe_to_add_dot_slash(url, base) or {
			// The rule takes such a URL as unsafe.
			assert wu_test_mentions_domain(url) || wu_test_mentions_domain(base), url
			unknown++
			if want {
				failures << '${json2.encode(url)} against ${base}: unknown, Node true'
			}
			continue
		}
		if got != want {
			failures << '${json2.encode(url)} against ${base}: ${got}, Node ${want}'
		}
	}
	assert failures == []
	assert unknown < 50
}

// A lone surrogate (WTF-8 in veslint's strings) is U+FFFD, as for Node's USVString.
fn test_lone_surrogate_is_replaced() {
	// Node: new URL('\ud800/\udfff?\ud83d#\ude00', 'https://example.com/a/b/').href
	assert wu_resolve('\xed\xa0\x80/\xed\xbf\xbf?\xed\xa0\xbd#\xed\xb8\x80', 'https://example.com/a/b/')! == 'https://example.com/a/b/%EF%BF%BD/%EF%BF%BD?%EF%BF%BD#%EF%BF%BD'
	// A pair of surrogates written as two WTF-8 sequences is not produced by veslint (it joins
	// them), but each half alone is replaced.
	assert wu_resolve('a\xed\xa0\xbd', 'file:///a/b.html')! == 'file:///a/a%EF%BF%BD'
}
