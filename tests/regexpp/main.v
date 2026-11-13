// Differential test driver: reads cases.txt (see tests/regexpp/cases.mjs) and writes the same canonical dump as
// tests/regexpp/oracle.cjs, using the V port of regexpp.
module main

import os
import math
import strings
import regexpp

fn esc(s string) string {
	mut b := strings.new_builder(s.len + 2)
	b.write_u8(`"`)
	for c in regexpp.to_utf16(s) {
		if c >= 0x20 && c < 0x7f && c != 0x22 && c != 0x5c {
			b.write_u8(u8(c))
		} else {
			b.write_string('\\u${int(c):04x}')
		}
	}
	b.write_u8(`"`)
	return b.str()
}

fn num(x f64) string {
	if math.is_inf(x, 1) {
		return 'Infinity'
	}
	if x == math.floor(x) && math.abs(x) <= 9007199254740992.0 {
		return i64(x).str()
	}
	return 'f${math.f64_bits(x):016x}'
}

fn unhex(h string) []u16 {
	mut out := []u16{cap: h.len / 4}
	mut i := 0
	for i + 4 <= h.len {
		out << u16(h[i..i + 4].parse_uint(16, 32) or { 0 })
		i += 4
	}
	return out
}

fn res_err(err IError) string {
	if err is regexpp.SyntaxError {
		return 'err ${err.index} ${esc(err.message)}'
	}
	return 'crash'
}

fn dump_ast(mut out strings.Builder, a &regexpp.Ast) {
	events := a.visit_events()
	mut ids := map[int]int{}
	mut order := []int{}
	mut w := strings.new_builder(events.len * 3)
	for e in events {
		if e.enter {
			if e.node !in ids {
				ids[e.node] = ids.len
				order << e.node
			}
			w.write_string('+${ids[e.node]}')
		} else {
			w.write_string('-${ids[e.node]}')
		}
	}
	r := fn [ids] (i int) string {
		if i < 0 {
			return 'null'
		}
		return if i in ids { '#${ids[i]}' } else { '#?' }
	}
	rl := fn [r] (l []int) string {
		return '[' + l.map(r(it)).join(',') + ']'
	}
	for i in order {
		n := a.nodes[i]
		mut kv := [][]string{}
		kv << ['type', esc(n.kind.type_name())]
		kv << ['parent', r(n.parent)]
		kv << ['start', n.start.str()]
		kv << ['end', n.end.str()]
		kv << ['raw', esc(a.raw(i))]
		match n.kind {
			.pattern, .class_string_disjunction {
				kv << ['alternatives', rl(n.alternatives)]
			}
			.alternative, .string_alternative {
				kv << ['elements', rl(n.elements)]
			}
			.group {
				kv << ['modifiers', r(n.modifiers)]
				kv << ['alternatives', rl(n.alternatives)]
			}
			.capturing_group {
				kv << ['name', if n.has_name { esc(n.name) } else { 'null' }]
				kv << ['alternatives', rl(n.alternatives)]
				kv << ['references', rl(n.references)]
			}
			.quantifier {
				kv << ['min', num(n.min)]
				kv << ['max', num(n.max)]
				kv << ['greedy', n.greedy.str()]
				kv << ['element', r(n.element)]
			}
			.character_class {
				kv << ['unicodeSets', n.unicode_sets.str()]
				kv << ['negate', n.negate.str()]
				kv << ['elements', rl(n.elements)]
			}
			.character_class_range {
				kv << ['min', r(n.min_char)]
				kv << ['max', r(n.max_char)]
			}
			.class_intersection, .class_subtraction {
				kv << ['left', r(n.left)]
				kv << ['right', r(n.right)]
			}
			.expression_character_class {
				kv << ['negate', n.negate.str()]
				kv << ['expression', r(n.expression)]
			}
			.assertion {
				kv << ['kind', esc(n.assertion_kind.str())]
				if n.assertion_kind in [.word, .lookahead, .lookbehind] {
					kv << ['negate', n.negate.str()]
				}
				if n.assertion_kind in [.lookahead, .lookbehind] {
					kv << ['alternatives', rl(n.alternatives)]
				}
			}
			.character {
				kv << ['value', n.value.str()]
			}
			.character_set {
				kv << ['kind', esc(n.set_kind.str())]
				if n.set_kind != .any {
					kv << ['negate', n.negate.str()]
				}
				if n.set_kind == .property {
					kv << ['strings', n.strings.str()]
					kv << ['key', esc(n.key)]
					kv << ['value', if n.has_value { esc(n.value_str) } else { 'null' }]
				}
			}
			.backreference {
				kv << ['ref', if n.ref_is_name { esc(n.ref_name) } else { n.ref_num.str() }]
				kv << ['ambiguous', n.ambiguous.str()]
				kv << ['resolved', if n.ambiguous { rl(n.resolved) } else { r(n.resolved[0]) }]
			}
			.flags {
				kv << ['global', n.global.str()]
				kv << ['ignoreCase', n.ignore_case.str()]
				kv << ['multiline', n.multiline.str()]
				kv << ['unicode', n.unicode.str()]
				kv << ['sticky', n.sticky.str()]
				kv << ['dotAll', n.dot_all.str()]
				kv << ['hasIndices', n.has_indices.str()]
				kv << ['unicodeSets', n.unicode_sets.str()]
			}
			.regexp_literal {
				kv << ['pattern', r(n.pattern)]
				kv << ['flags', r(n.flags)]
			}
			.modifiers {
				kv << ['add', r(n.add)]
				kv << ['remove', r(n.remove)]
			}
			.modifier_flags {
				kv << ['ignoreCase', n.ignore_case.str()]
				kv << ['multiline', n.multiline.str()]
				kv << ['dotAll', n.dot_all.str()]
			}
		}
		kv.sort(a[0] < b[0])
		out.write_string('N ')
		out.write_string(kv.map('${it[0]}=${it[1]}').join(' '))
		out.write_u8(`\n`)
	}
	out.write_string('W ')
	out.write_string(w.str())
	out.write_u8(`\n`)
}

fn main() {
	lines := os.read_lines(os.args[1]) or { panic(err) }
	mut out := strings.new_builder(1 << 24)
	mut line_no := 0
	for line in lines {
		if line == '' {
			continue
		}
		line_no++
		f := line.split('\t')
		kind := f[0]
		out.write_string('#${line_no} ${kind}\n')
		opts := regexpp.Options{
			ecma_version: f[1].int()
			strict:       f[2] == '1'
		}
		if kind == 'P' {
			flags := regexpp.PatternFlags{
				unicode:      f[3].contains('u')
				unicode_sets: f[3].contains('v')
			}
			start := f[4].int()
			end := f[5].int()
			src := unhex(f[6])
			ev := regexpp.validate_pattern_events(src, start, end, flags, opts)
			// validate_pattern must agree with the events variant
			mut plain := 'ok'
			regexpp.validate_pattern(src, start, end, flags, opts) or { plain = res_err(err) }
			vres := if ev.has_error { res_err(ev.error) } else { 'ok' }
			if plain != vres {
				out.write_string('MISMATCH validate_pattern ${plain}\n')
			}
			out.write_string('V ${vres}\n')
			mut es := []string{}
			for e in ev.events {
				es << match e.kind {
					.pattern_enter { 'P${e.start}' }
					.pattern_leave { 'Q${e.start},${e.end}' }
					.character { 'C${e.start},${e.end},${e.value}' }
				}
			}
			out.write_string('E ${es.join(' ')}\n')
			a := regexpp.parse_pattern(src, start, end, flags, opts) or {
				out.write_string('A ${res_err(err)}\n')
				continue
			}
			out.write_string('A ok\n')
			dump_ast(mut out, a)
		} else {
			start := f[3].int()
			end := f[4].int()
			src := unhex(f[5])
			if kind == 'F' {
				mut vr := 'ok'
				regexpp.validate_flags(src, start, end, opts) or { vr = res_err(err) }
				out.write_string('V ${vr}\n')
				a := regexpp.parse_flags(src, start, end, opts) or {
					out.write_string('A ${res_err(err)}\n')
					continue
				}
				out.write_string('A ok\n')
				dump_ast(mut out, a)
			} else {
				mut vr := 'ok'
				regexpp.validate_literal(src, start, end, opts) or { vr = res_err(err) }
				out.write_string('V ${vr}\n')
				a := regexpp.parse_literal(src, start, end, opts) or {
					out.write_string('A ${res_err(err)}\n')
					continue
				}
				out.write_string('A ok\n')
				dump_ast(mut out, a)
			}
		}
	}
	os.write_file(os.args[2], out.str()) or { panic(err) }
}
