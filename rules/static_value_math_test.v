module rules

import math

// Values of Math that getStaticValue gives, as the bits of the doubles of Node 26.8.2 (V8 14.6).

fn math_test_abs(x f64) u64 {
	math_object := stv_builtin_global('Math') or { panic('no Math') }
	mut ctx := StvContext{}
	result := stv_call_function(js_any_function('Math.abs'), math_object, true, [
		js_any_number(x),
	], mut ctx) or { panic('Math.abs is not static') }
	assert result.kind == .number_
	return math.f64_bits(result.number)
}

// Math.abs clears the sign of a zero too: `Object.is(Math.abs(-0), 0)`.
fn test_math_abs_of_negative_zero() {
	assert math_test_abs(-0.0) == u64(0)
	assert math_test_abs(0.0) == u64(0)
	assert math_test_abs(-1.5) == u64(0x3ff8000000000000)
	assert math_test_abs(1.5) == u64(0x3ff8000000000000)
	assert math_test_abs(-5e-324) == u64(1)
	assert math_test_abs(math.inf(-1)) == u64(0x7ff0000000000000)
	assert math.is_nan(math.f64_from_bits(math_test_abs(math.nan())))
}

// The value properties of Math: V8 computes LOG10E as log10(E), which is not 1 / LN10.
fn test_math_constants() {
	math_object := stv_builtin_global('Math') or { panic('no Math') }
	expected := {
		'E':       u64(0x4005bf0a8b145769)
		'LN10':    0x40026bb1bbb55516
		'LN2':     0x3fe62e42fefa39ef
		'LOG10E':  0x3fdbcb7b1526e50e
		'LOG2E':   0x3ff71547652b82fe
		'PI':      0x400921fb54442d18
		'SQRT1_2': 0x3fe6a09e667f3bcd
		'SQRT2':   0x3ff6a09e667f3bcd
	}
	for name, bits in expected {
		value := stv_get(math_object, js_any_text(name)) or { panic('Math.${name} is not static') }
		assert value.kind == .number_
		assert math.f64_bits(value.number) == bits, 'Math.${name}'
	}
}

fn math_test_pow(x f64, y f64) u64 {
	math_object := stv_builtin_global('Math') or { panic('no Math') }
	mut ctx := StvContext{}
	result := stv_call_function(js_any_function('Math.pow'), math_object, true, [
		js_any_number(x),
		js_any_number(y),
	], mut ctx) or { panic('Math.pow is not static') }
	assert result.kind == .number_
	// `**` is the same function in V8.
	assert math.f64_bits(stv_power(x, y)) == math.f64_bits(result.number)
	return math.f64_bits(result.number)
}

// An exponent of 2 is `x * x` and one of 0.5 is `sqrt(x + 0)` in V8: for these bases the C
// library's pow gives the neighbouring double.
fn test_power_of_two_and_of_a_half() {
	squares := {
		u64(0x4010e09bfe4571a6): u64(0x4031cd89124b5a04)
		0x4012647c9ccf8d5e:      0x4035248f7a45a50c
		0x40174b5c4375a7fa:      0x4040f5061a7f5d6e
		0x401fb40a81c14c4e:      0x404f68c9519db599
		0x4014c50f646f33bd:      0x403af621862e027a
		0x401d93b60d62f4a8:      0x404b5663ccea10e4
	}
	for base, result in squares {
		assert math_test_pow(math.f64_from_bits(base), 2) == result, '${base:x} ** 2'
	}
	roots := {
		u64(0x3ff841c666906e7c): u64(0x3ff3b35606b42b6a)
		0x401f7741ceb04b06:      0x40067011c22dd87d
		0x4021eb9f6e392f54:      0x4007f2666f0c4dc5
		0x401a20a6ab51a8c6:      0x4004722fe678d015
		0x4022466e17070e74:      0x40082ec67a65699b
		0x4020eb3944fba522:      0x400744a011c7eae0
	}
	for base, result in roots {
		assert math_test_pow(math.f64_from_bits(base), 0.5) == result, '${base:x} ** 0.5'
	}
}

// The cases ECMAScript sets apart, and plain calls of pow.
fn test_power_special_cases() {
	infinity := u64(0x7ff0000000000000)
	assert math_test_pow(-0.0, 0.5) == u64(0)
	assert math_test_pow(0.0, 0.5) == u64(0)
	assert math_test_pow(math.inf(-1), 0.5) == infinity
	assert math_test_pow(math.inf(1), 0.5) == infinity
	assert math.is_nan(math.f64_from_bits(math_test_pow(-4, 0.5)))
	assert math_test_pow(-0.0, 2) == u64(0)
	assert math_test_pow(math.inf(-1), 2) == infinity
	assert math_test_pow(-4, 2) == u64(0x4030000000000000)
	assert math_test_pow(-0.0, -0.5) == infinity
	assert math_test_pow(math.inf(-1), -0.5) == u64(0)
	assert math.is_nan(math.f64_from_bits(math_test_pow(1, math.inf(1))))
	assert math.is_nan(math.f64_from_bits(math_test_pow(-1, math.inf(-1))))
	assert math.is_nan(math.f64_from_bits(math_test_pow(2, math.nan())))
	assert math.is_nan(math.f64_from_bits(math_test_pow(math.nan(), 2)))
	assert math_test_pow(math.nan(), 0) == u64(0x3ff0000000000000)
	assert math_test_pow(2, 8) == u64(0x4070000000000000)
	assert math_test_pow(1.1, 3) == u64(0x3ff54bc6a7ef9db4)
	assert math_test_pow(9.9, 2.5) == u64(0x40734619a9fc9124)
}
