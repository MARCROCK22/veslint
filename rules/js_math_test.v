module rules

import json2
import math
import os
import strconv

// The cases come from tools/gen_math_cases.mjs: the bits of what V8's Math functions give for
// chosen arguments, and digests of what they give for arguments built from a seed, built here the
// same way.

const math_unary_names = ['acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'cbrt', 'cos', 'cosh',
	'exp', 'expm1', 'log', 'log1p', 'log2', 'log10', 'sin', 'sinh', 'tan', 'tanh']

fn math_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'math_cases.json')) or { panic(err) }
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

fn math_from_hex(text string) f64 {
	return math.f64_from_bits(strconv.parse_uint(text, 16, 64) or { panic(err) })
}

// math_hex writes the bits of a double, with one NaN for all of them, as the generator does.
fn math_hex(x f64) string {
	return if math.is_nan(x) { '7ff8000000000000' } else { '${math.f64_bits(x):016x}' }
}

fn math_unary(name string, x f64) f64 {
	return js_math_function('Math.${name}', x) or { panic('no Math.${name}') }
}

fn test_chosen_arguments_match_v8() {
	data := math_cases()
	cases := (data['cases'] or { panic('no cases') }).as_map()
	mut checked := 0
	for name in math_unary_names {
		for item in (cases[name] or { panic('no ${name}') }).as_array() {
			pair := item.as_array()
			x := math_from_hex(pair[0].str())
			assert math_hex(math_unary(name, x)) == pair[1].str(), 'Math.${name}(${x}) (${pair[0].str()})'
			checked++
		}
	}
	for item in (cases['atan2'] or { panic('no atan2') }).as_array() {
		triple := item.as_array()
		y := math_from_hex(triple[0].str())
		x := math_from_hex(triple[1].str())
		assert math_hex(js_math_atan2(y, x)) == triple[2].str(), 'Math.atan2(${y}, ${x})'
		checked++
	}
	for item in (cases['hypot'] or { panic('no hypot') }).as_array() {
		pair := item.as_array()
		args := pair[0].as_array().map(math_from_hex(it.str()))
		assert math_hex(js_math_hypot(args)) == pair[1].str(), 'Math.hypot(${args})'
		checked++
	}
	assert checked > 1000
}

// MathGenerator is the generator's linear congruential generator.
struct MathGenerator {
mut:
	state u32
}

fn (mut g MathGenerator) next() u32 {
	g.state = g.state * 1103515245 + 12345
	return g.state
}

fn (mut g MathGenerator) unit() f64 {
	return f64(g.next()) / 4294967296.0
}

// math_argument builds an argument of a kind as the generator does, with its numbers in the same
// order.
fn math_argument(mode string, mut g MathGenerator) f64 {
	match mode {
		'bits' {
			high := g.next()
			return js_math_words(high, g.next())
		}
		'unit' {
			return g.unit() * 2 - 1
		}
		'small' {
			return g.unit() * 32 - 16
		}
		'exp' {
			return g.unit() * 1500 - 750
		}
		'wide', 'huge' {
			sign := g.next() & 0x80000000
			exponent := if mode == 'wide' {
				u32(1023 - 60) + g.next() % 121
			} else {
				u32(1023) +
					g.next() % 1024
			}
			significand := g.next() & 0xfffff
			return js_math_words(sign | (exponent << 20) | significand, g.next())
		}
		'pio2' {
			k := f64(i64(g.next() % 200001) - 100000)
			return k * 1.5707963267948966 + (g.unit() - 0.5) * 9.313225746154785e-10
		}
		'near1' {
			return 1 + (g.unit() - 0.5) * 9.5367431640625e-7
		}
		else {
			panic('unknown kind of argument ${mode}')
		}
	}
}

fn math_arguments(mode string, count int, start u32) []f64 {
	mut g := MathGenerator{
		state: start
	}
	mut out := []f64{cap: count}
	for _ in 0 .. count {
		out << math_argument(mode, mut g)
	}
	return out
}

// math_digests are the generator's FNV-1a digests of the bits of the results, a chunk at a time.
fn math_digests(results []f64, chunk_size int) []string {
	mut out := []string{}
	for start := 0; start < results.len; start += chunk_size {
		mut h := u32(0x811c9dc5)
		for x in results[start..math.min(start + chunk_size, results.len)] {
			bits := if math.is_nan(x) { u64(0x7ff8000000000000) } else { math.f64_bits(x) }
			h = (h ^ u32(bits & 0xffffffff)) * 0x01000193
			h = (h ^ u32(bits >> 32)) * 0x01000193
		}
		out << '${h:08x}'
	}
	return out
}

fn math_expected(data map[string]json2.Any, name string, mode string) []string {
	digests := (data['digests'] or { panic('no digests') }).as_map()
	return ((digests[name] or { panic('no ${name}') }).as_map()[mode] or { panic('no ${mode}') }).as_array().map(it.str())
}

fn test_arguments_from_the_seed_match_v8() {
	data := math_cases()
	seed := u32((data['seed'] or { panic('no seed') }).i64())
	count := (data['perMode'] or { panic('no perMode') }).int()
	chunk_size := (data['chunkSize'] or { panic('no chunkSize') }).int()
	modes := (data['modes'] or { panic('no modes') }).as_array().map(it.str())
	for i, mode in modes {
		arguments := math_arguments(mode, count, seed + u32(i))
		for name in math_unary_names {
			results := arguments.map(math_unary(name, it))
			assert math_digests(results, chunk_size) == math_expected(data, name, mode), 'Math.${name} of the ${mode} arguments'
		}
		ys := math_arguments(mode, count, seed + 100 + u32(i))
		xs := math_arguments(mode, count, seed + 200 + u32(i))
		mut results := []f64{cap: count}
		for j, y in ys {
			results << js_math_atan2(y, xs[j])
		}
		assert math_digests(results, chunk_size) == math_expected(data, 'atan2', mode), 'Math.atan2 of the ${mode} arguments'
	}
	// hypot of 0 to 6 arguments: a special one one time in eight, else a `wide` one.
	specials := (data['specials'] or { panic('no specials') }).as_array().map(math_from_hex(it.str()))
	mut g := MathGenerator{
		state: seed + 300
	}
	mut results := []f64{cap: count}
	for _ in 0 .. count {
		mut args := []f64{}
		for _ in 0 .. g.next() % 7 {
			args << if g.next() % 8 == 0 {
				specials[g.next() % u32(specials.len)]
			} else {
				math_argument('wide', mut g)
			}
		}
		results << js_math_hypot(args)
	}
	assert math_digests(results, chunk_size) == math_expected(data, 'hypot', 'mixed'), 'Math.hypot'
}
