module rules

import math

// The transcendental functions of Math as V8 computes them, for static_value.v: a port of V8's
// src/base/ieee754.cc (fdlibm) as Node 26.13.0 builds it, without V8_USE_LIBM_TRIG_FUNCTIONS, so
// sin and cos are fdlibm's too, and of Math.hypot (src/builtins/math.tq). Each operation is the
// same double operation, in the same order, as in V8's C++, so the results are V8's to the last
// bit: rules/js_math_test.v checks that against V8 itself on millions of arguments
// (tools/gen_math_cases.mjs). The words of a double are 32-bit integers, as in fdlibm; V's `int`
// has 64 bits, so they are i32 and u32 here, and what wraps in V8 wraps in u32.

$if gcc || clang {
	// a*b+c must not become a fused multiply-add, which gcc does by default on arm64 and which
	// changes the last bit.
	#flag -ffp-contract=off
}

// js_math_function computes the Math function `name` (`Math.sin`) of one number; none for the
// functions of other arities and for those it does not have.
fn js_math_function(name string, x f64) ?f64 {
	return match name {
		'Math.acos' { js_math_acos(x) }
		'Math.acosh' { js_math_acosh(x) }
		'Math.asin' { js_math_asin(x) }
		'Math.asinh' { js_math_asinh(x) }
		'Math.atan' { js_math_atan(x) }
		'Math.atanh' { js_math_atanh(x) }
		'Math.cbrt' { js_math_cbrt(x) }
		'Math.cos' { js_math_cos(x) }
		'Math.cosh' { js_math_cosh(x) }
		'Math.exp' { js_math_exp(x) }
		'Math.expm1' { js_math_expm1(x) }
		'Math.log' { js_math_log(x) }
		'Math.log1p' { js_math_log1p(x) }
		'Math.log2' { js_math_log2(x) }
		'Math.log10' { js_math_log10(x) }
		'Math.sin' { js_math_sin(x) }
		'Math.sinh' { js_math_sinh(x) }
		'Math.tan' { js_math_tan(x) }
		'Math.tanh' { js_math_tanh(x) }
		else { none }
	}
}

// js_math_fabs is C's fabs: the sign cleared, also the one of -0 (V's math.abs keeps it).
fn js_math_fabs(x f64) f64 {
	return math.f64_from_bits(math.f64_bits(x) & 0x7fffffffffffffff)
}

// GET_HIGH_WORD: the more significant 32 bits of a double, as a signed integer.
fn js_math_high(x f64) i32 {
	return i32(u32(math.f64_bits(x) >> 32))
}

// GET_LOW_WORD.
fn js_math_low(x f64) u32 {
	return u32(math.f64_bits(x) & 0xffffffff)
}

// INSERT_WORDS.
fn js_math_words(high u32, low u32) f64 {
	return math.f64_from_bits((u64(high) << 32) | u64(low))
}

// SET_HIGH_WORD.
fn js_math_set_high(x f64, high u32) f64 {
	return math.f64_from_bits((math.f64_bits(x) & 0xffffffff) | (u64(high) << 32))
}

// SET_LOW_WORD.
fn js_math_set_low(x f64, low u32) f64 {
	return math.f64_from_bits((math.f64_bits(x) & 0xffffffff00000000) | u64(low))
}

// 396 hexadecimal digits of 2/pi, 24 bits at a time.
const js_math_two_over_pi = [i32(0xA2F983), 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62, 0x95993C,
	0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A, 0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB,
	0x1CB129, 0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41, 0x3991D6, 0x398353, 0x39F49C,
	0x845F8B, 0xBDF928, 0x3B1FF8, 0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF, 0x27CB09,
	0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5, 0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F,
	0x8D5D08, 0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3, 0x91615E, 0xE61B08, 0x659985,
	0x5F14A0, 0x68408D, 0xFFD880, 0x4D7327, 0x310606, 0x1556CA, 0x73A8C9, 0x60E27B, 0xC08C6B]

// The high words of n*pi/2 for n from 1 to 32.
const js_math_npio2_hw = [i32(0x3FF921FB), 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C,
	0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C, 0x40346B9C, 0x4035FDBB,
	0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A, 0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C,
	0x4042106C, 0x4042D97C, 0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB,
	0x404858EB, 0x404921FB]

// pi/2 cut into chunks of 24 bits.
const js_math_pio2_chunks = [1.57079625129699707031e+00, 7.54978941586159635335e-08,
	5.39030252995776476554e-15, 3.28200341580791294123e-22, 1.27065575308067607349e-29,
	1.22933308981111328932e-36, 2.73370053816464559624e-44, 2.16741683877804819444e-51]

// js_math_rem_pio2 ports __ieee754_rem_pio2: n and x - n*pi/2 as y0 + y1.
fn js_math_rem_pio2(x f64) (i32, f64, f64) {
	zero := 0.00000000000000000000e+00
	half := 5.00000000000000000000e-01
	two24 := 1.67772160000000000000e+07
	invpio2 := 6.36619772367581382433e-01
	pio2_1 := 1.57079632673412561417e+00
	pio2_1t := 6.07710050650619224932e-11
	pio2_2 := 6.07710050630396597660e-11
	pio2_2t := 2.02226624879595063154e-21
	pio2_3 := 2.02226624871116645580e-21
	pio2_3t := 8.47842766036889956997e-32

	hx := js_math_high(x)
	ix := hx & 0x7FFFFFFF
	if ix <= 0x3FE921FB {
		return 0, x, 0.0
	}
	if ix < 0x4002D97C {
		// |x| < 3pi/4: n = 1 or -1.
		if hx > 0 {
			mut z := x - pio2_1
			if ix != 0x3FF921FB {
				y0 := z - pio2_1t
				return 1, y0, (z - y0) - pio2_1t
			}
			z -= pio2_2
			y0 := z - pio2_2t
			return 1, y0, (z - y0) - pio2_2t
		}
		mut z := x + pio2_1
		if ix != 0x3FF921FB {
			y0 := z + pio2_1t
			return -1, y0, (z - y0) + pio2_1t
		}
		z += pio2_2
		y0 := z + pio2_2t
		return -1, y0, (z - y0) + pio2_2t
	}
	if ix <= 0x413921FB {
		// |x| ~<= 2^19*(pi/2), medium size.
		mut t := js_math_fabs(x)
		n := i32(t * invpio2 + half)
		nf := f64(n)
		mut r := t - nf * pio2_1
		mut w := nf * pio2_1t
		mut y0 := 0.0
		if n < 32 && ix != js_math_npio2_hw[n - 1] {
			y0 = r - w
		} else {
			j := ix >> 20
			y0 = r - w
			mut high := u32(math.f64_bits(y0) >> 32)
			mut i := j - i32((high >> 20) & 0x7FF)
			if i > 16 {
				t = r
				w = nf * pio2_2
				r = t - w
				w = nf * pio2_2t - ((t - r) - w)
				y0 = r - w
				high = u32(math.f64_bits(y0) >> 32)
				i = j - i32((high >> 20) & 0x7FF)
				if i > 49 {
					t = r
					w = nf * pio2_3
					r = t - w
					w = nf * pio2_3t - ((t - r) - w)
					y0 = r - w
				}
			}
		}
		y1 := (r - y0) - w
		if hx < 0 {
			return -n, -y0, -y1
		}
		return n, y0, y1
	}
	if ix >= 0x7FF00000 {
		d := x - x
		return 0, d, d
	}
	// z = scalbn(|x|, ilogb(x) - 23), cut into three 24-bit pieces.
	e0 := (ix >> 20) - 1046
	mut z := js_math_words(u32(ix - i32(u32(e0) << 20)), js_math_low(x))
	mut tx := [3]f64{}
	for i in 0 .. 2 {
		tx[i] = f64(i32(z))
		z = (z - tx[i]) * two24
	}
	tx[2] = z
	mut nx := 3
	for tx[nx - 1] == zero {
		nx--
	}
	n, y0, y1 := js_math_kernel_rem_pio2(tx[..], e0, nx)
	if hx < 0 {
		return -n, -y0, -y1
	}
	return n, y0, y1
}

// js_math_kernel_rem_pio2 ports __kernel_rem_pio2 with the precision V8 asks (prec 2, two doubles
// out): the last three bits of n, and x - n*pi/2 as y0 + y1, for x given as nx 24-bit pieces
// scaled by 2^e0.
fn js_math_kernel_rem_pio2(x []f64, e0 i32, nx int) (i32, f64, f64) {
	two24 := 1.67772160000000000000e+07
	twon24 := 5.96046447753906250000e-08
	mut iq := [20]i32{}
	mut f := [20]f64{}
	mut fq := [20]f64{}
	mut q := [20]f64{}

	// init_jk[2]: the initial number of terms of 2/pi, minus one.
	jk := 4
	jp := jk
	jx := nx - 1
	mut jv := int((e0 - 3) / 24)
	if jv < 0 {
		jv = 0
	}
	mut q0 := e0 - i32(24 * (jv + 1))

	// f[0] to f[jx+jk], where f[jx+jk] = two_over_pi[jv+jk].
	mut j := jv - jx
	for i := 0; i <= jx + jk; i++ {
		f[i] = if j < 0 { 0.0 } else { f64(js_math_two_over_pi[j]) }
		j++
	}
	for i := 0; i <= jk; i++ {
		mut fw := 0.0
		for k := 0; k <= jx; k++ {
			fw += x[k] * f[jx + i - k]
		}
		q[i] = fw
	}

	mut jz := jk
	mut z := 0.0
	mut n := i32(0)
	mut ih := i32(0)
	for {
		// Distill q[] into iq[] reversingly.
		mut i := 0
		j = jz
		z = q[jz]
		for j > 0 {
			fw := f64(i32(twon24 * z))
			iq[i] = i32(z - two24 * fw)
			z = q[j - 1] + fw
			i++
			j--
		}
		// n, and the fraction in z.
		z = math.ldexp(z, int(q0))
		z -= 8.0 * math.floor(z * 0.125)
		n = i32(z)
		z -= f64(n)
		ih = 0
		if q0 > 0 {
			// iq[jz-1] tells n.
			k := iq[jz - 1] >> (24 - q0)
			n += k
			iq[jz - 1] -= k << (24 - q0)
			ih = iq[jz - 1] >> (23 - q0)
		} else if q0 == 0 {
			ih = iq[jz - 1] >> 23
		} else if z >= 0.5 {
			ih = 2
		}
		if ih > 0 {
			// q > 0.5: 1 - q.
			n += 1
			mut carry := 0
			for k := 0; k < jz; k++ {
				m := iq[k]
				if carry == 0 {
					if m != 0 {
						carry = 1
						iq[k] = 0x1000000 - m
					}
				} else {
					iq[k] = 0xFFFFFF - m
				}
			}
			if q0 == 1 {
				iq[jz - 1] &= 0x7FFFFF
			} else if q0 == 2 {
				iq[jz - 1] &= 0x3FFFFF
			}
			if ih == 2 {
				z = 1.0 - z
				if carry != 0 {
					z -= math.ldexp(1.0, int(q0))
				}
			}
		}
		// Recomputation with more terms when the fraction cancelled.
		if z == 0.0 {
			mut m := i32(0)
			for k := jz - 1; k >= jk; k-- {
				m |= iq[k]
			}
			if m == 0 {
				mut k := 1
				for jk >= k && iq[jk - k] == 0 {
					k++
				}
				for t := jz + 1; t <= jz + k; t++ {
					f[jx + t] = f64(js_math_two_over_pi[jv + t])
					mut fw := 0.0
					for s := 0; s <= jx; s++ {
						fw += x[s] * f[jx + t - s]
					}
					q[t] = fw
				}
				jz += k
				continue
			}
		}
		break
	}

	// Chop off zero terms, or break z into 24 bits.
	if z == 0.0 {
		jz -= 1
		q0 -= 24
		for iq[jz] == 0 {
			jz--
			q0 -= 24
		}
	} else {
		z = math.ldexp(z, -int(q0))
		if z >= two24 {
			fw := f64(i32(twon24 * z))
			iq[jz] = i32(z - two24 * fw)
			jz += 1
			q0 += 24
			iq[jz] = i32(fw)
		} else {
			iq[jz] = i32(z)
		}
	}

	// The integer chunks as doubles.
	mut fw := math.ldexp(1.0, int(q0))
	for i := jz; i >= 0; i-- {
		q[i] = fw * f64(iq[i])
		fw *= twon24
	}

	// PIo2[0..jp] * q[jz..0].
	for i := jz; i >= 0; i-- {
		fw = 0.0
		for k := 0; k <= jp && k <= jz - i; k++ {
			fw += js_math_pio2_chunks[k] * q[i + k]
		}
		fq[jz - i] = fw
	}

	// Compress fq[] into y0 and y1.
	fw = 0.0
	for i := jz; i >= 0; i-- {
		fw += fq[i]
	}
	y0 := if ih == 0 { fw } else { -fw }
	fw = fq[0] - fw
	for i := 1; i <= jz; i++ {
		fw += fq[i]
	}
	y1 := if ih == 0 { fw } else { -fw }
	return n & 7, y0, y1
}

// js_math_kernel_cos ports __kernel_cos: cos(x + y) for |x| ~<= pi/4.
fn js_math_kernel_cos(x f64, y f64) f64 {
	one := 1.00000000000000000000e+00
	c1 := 4.16666666666666019037e-02
	c2 := -1.38888888888741095749e-03
	c3 := 2.48015872894767294178e-05
	c4 := -2.75573143513906633035e-07
	c5 := 2.08757232129817482790e-09
	c6 := -1.13596475577881948265e-11

	ix := js_math_high(x) & 0x7FFFFFFF
	if ix < 0x3E400000 {
		if i32(x) == 0 {
			return one
		}
	}
	z := x * x
	r := z * (c1 + z * (c2 + z * (c3 + z * (c4 + z * (c5 + z * c6)))))
	if ix < 0x3FD33333 {
		return one - (0.5 * z - (z * r - x * y))
	}
	qx := if ix > 0x3FE90000 { 0.28125 } else { js_math_words(u32(ix - 0x00200000), 0) }
	iz := 0.5 * z - qx
	a := one - qx
	return a - (iz - (z * r - x * y))
}

// js_math_kernel_sin ports __kernel_sin: sin(x + y) for |x| ~<= pi/4; y is 0 when iy is.
fn js_math_kernel_sin(x f64, y f64, iy int) f64 {
	half := 5.00000000000000000000e-01
	s1 := -1.66666666666666324348e-01
	s2 := 8.33333333332248946124e-03
	s3 := -1.98412698298579493134e-04
	s4 := 2.75573137070700676789e-06
	s5 := -2.50507602534068634195e-08
	s6 := 1.58969099521155010221e-10

	ix := js_math_high(x) & 0x7FFFFFFF
	if ix < 0x3E400000 {
		if i32(x) == 0 {
			return x
		}
	}
	z := x * x
	v := z * x
	r := s2 + z * (s3 + z * (s4 + z * (s5 + z * s6)))
	if iy == 0 {
		return x + v * (s1 + z * r)
	}
	return x - ((z * (half * y - v * r) - y) - v * s1)
}

const js_math_tan_coefficients = [3.33333333333334091986e-01, 1.33333333333201242699e-01,
	5.39682539762260521377e-02, 2.18694882948595424599e-02, 8.86323982359930005737e-03,
	3.59207910759131235356e-03, 1.45620945432529025516e-03, 5.88041240820264096874e-04,
	2.46463134818469906812e-04, 7.81794442939557092300e-05, 7.14072491382608190305e-05,
	-1.85586374855275456654e-05, 2.59073051863633712884e-05]

// js_math_kernel_tan ports __kernel_tan: tan(x + y) for |x| ~<= pi/4 if iy is 1, -1/tan(x + y)
// if it is -1.
fn js_math_kernel_tan(x_ f64, y_ f64, iy int) f64 {
	one := 1.00000000000000000000e+00
	pio4 := 7.85398163397448278999e-01
	pio4lo := 3.06161699786838301793e-17

	mut x := x_
	mut y := y_
	hx := js_math_high(x)
	ix := hx & 0x7FFFFFFF
	if ix < 0x3E300000 {
		if i32(x) == 0 {
			low := js_math_low(x)
			if ((u32(ix) | low) | u32(iy + 1)) == 0 {
				return one / js_math_fabs(x)
			}
			if iy == 1 {
				return x
			}
			// -1 / (x + y), carefully.
			w := x + y
			z := js_math_set_low(w, 0)
			v := y - (z - x)
			a := -one / w
			tt := js_math_set_low(a, 0)
			s := one + tt * z
			return tt + a * (s + tt * v)
		}
	}
	if ix >= 0x3FE59428 {
		// |x| >= 0.6744: tan(pi/4 - (pi/4 - x)).
		if hx < 0 {
			x = -x
			y = -y
		}
		z := pio4 - x
		w := pio4lo - y
		x = z + w
		y = 0.0
	}
	z := x * x
	mut w := z * z
	mut r := js_math_tan_coefficients[1] + w * (js_math_tan_coefficients[3] + w * (js_math_tan_coefficients[5] + w * (js_math_tan_coefficients[7] + w * (js_math_tan_coefficients[9] + w * js_math_tan_coefficients[11]))))
	mut v := z * (js_math_tan_coefficients[2] + w * (js_math_tan_coefficients[4] + w * (js_math_tan_coefficients[6] + w * (js_math_tan_coefficients[8] + w * (js_math_tan_coefficients[10] + w * js_math_tan_coefficients[12])))))
	s := z * x
	r = y + z * (s * (r + v) + y)
	r += js_math_tan_coefficients[0] * s
	w = x + r
	if ix >= 0x3FE59428 {
		v = f64(iy)
		return f64(1 - ((hx >> 30) & 2)) * (v - 2.0 * (x - (w * w / (w + v) - r)))
	}
	if iy == 1 {
		return w
	}
	// -1.0 / (x + r), accurately.
	zz := js_math_set_low(w, 0)
	vv := r - (zz - x)
	a := -1.0 / w
	tt := js_math_set_low(a, 0)
	ss := 1.0 + tt * zz
	return tt + a * (ss + tt * vv)
}

const js_math_one = 1.00000000000000000000e+00
const js_math_pio2_hi = 1.57079632679489655800e+00
const js_math_pio2_lo = 6.12323399573676603587e-17

// The coefficients of R(x^2) of asin and acos.
const js_math_ps0 = 1.66666666666666657415e-01
const js_math_ps1 = -3.25565818622400915405e-01
const js_math_ps2 = 2.01212532134862925881e-01
const js_math_ps3 = -4.00555345006794114027e-02
const js_math_ps4 = 7.91534994289814532176e-04
const js_math_ps5 = 3.47933107596021167570e-05
const js_math_qs1 = -2.40339491173441421878e+00
const js_math_qs2 = 2.02094576023350569471e+00
const js_math_qs3 = -6.88283971605453293030e-01
const js_math_qs4 = 7.70381505559019352791e-02

fn js_math_acos_p(z f64) f64 {
	return z * (js_math_ps0 + z * (js_math_ps1 + z * (js_math_ps2 + z * (js_math_ps3 + z * (js_math_ps4 +
		z * js_math_ps5)))))
}

fn js_math_acos_q(z f64) f64 {
	return js_math_one + z * (js_math_qs1 + z * (js_math_qs2 + z * (js_math_qs3 + z * js_math_qs4)))
}

fn js_math_acos(x f64) f64 {
	pi := 3.14159265358979311600e+00
	hx := js_math_high(x)
	ix := hx & 0x7FFFFFFF
	if ix >= 0x3FF00000 {
		if (u32(ix - 0x3FF00000) | js_math_low(x)) == 0 {
			// acos(1) = 0, acos(-1) = pi.
			return if hx > 0 { 0.0 } else { pi + 2.0 * js_math_pio2_lo }
		}
		return math.nan()
	}
	if ix < 0x3FE00000 {
		// |x| < 0.5.
		if ix <= 0x3C600000 {
			return js_math_pio2_hi + js_math_pio2_lo
		}
		z := x * x
		r := js_math_acos_p(z) / js_math_acos_q(z)
		return js_math_pio2_hi - (x - (js_math_pio2_lo - x * r))
	}
	if hx < 0 {
		// x < -0.5.
		z := (js_math_one + x) * 0.5
		p := js_math_acos_p(z)
		q := js_math_acos_q(z)
		s := math.sqrt(z)
		r := p / q
		w := r * s - js_math_pio2_lo
		return pi - 2.0 * (s + w)
	}
	// x > 0.5.
	z := (js_math_one - x) * 0.5
	s := math.sqrt(z)
	df := js_math_set_low(s, 0)
	c := (z - df * df) / (s + df)
	p := js_math_acos_p(z)
	q := js_math_acos_q(z)
	r := p / q
	w := r * s + c
	return 2.0 * (df + w)
}

fn js_math_acosh(x f64) f64 {
	one := 1.0
	ln2 := 6.93147180559945286227e-01
	hx := js_math_high(x)
	lx := js_math_low(x)
	if hx < 0x3FF00000 {
		return math.nan()
	}
	if hx >= 0x41B00000 {
		if hx >= 0x7FF00000 {
			return x + x
		}
		return js_math_log(x) + ln2
	}
	if (u32(hx - 0x3FF00000) | lx) == 0 {
		return 0.0
	}
	if hx > 0x40000000 {
		t := x * x
		return js_math_log(2.0 * x - one / (x + math.sqrt(t - one)))
	}
	t := x - one
	return js_math_log1p(t + math.sqrt(2.0 * t + t * t))
}

fn js_math_asin(x f64) f64 {
	huge := 1.000e+300
	pio4_hi := 7.85398163397448278999e-01
	hx := js_math_high(x)
	ix := hx & 0x7FFFFFFF
	if ix >= 0x3FF00000 {
		if (u32(ix - 0x3FF00000) | js_math_low(x)) == 0 {
			return x * js_math_pio2_hi + x * js_math_pio2_lo
		}
		return math.nan()
	}
	if ix < 0x3FE00000 {
		// |x| < 0.5.
		mut t := 0.0
		if ix < 0x3E400000 {
			if huge + x > js_math_one {
				return x
			}
		} else {
			t = x * x
		}
		w := js_math_acos_p(t) / js_math_acos_q(t)
		return x + x * w
	}
	// 1 > |x| >= 0.5.
	mut w := js_math_one - js_math_fabs(x)
	mut t := w * 0.5
	mut p := js_math_acos_p(t)
	mut q := js_math_acos_q(t)
	s := math.sqrt(t)
	if ix >= 0x3FEF3333 {
		// |x| > 0.975.
		w = p / q
		t = js_math_pio2_hi - (2.0 * (s + s * w) - js_math_pio2_lo)
	} else {
		w = js_math_set_low(s, 0)
		c := (t - w * w) / (s + w)
		r := p / q
		p = 2.0 * s * r - (js_math_pio2_lo - 2.0 * c)
		q = pio4_hi - 2.0 * w
		t = pio4_hi - (p - q)
	}
	return if hx > 0 { t } else { -t }
}

fn js_math_asinh(x f64) f64 {
	ln2 := 6.93147180559945286227e-01
	huge := 1.00000000000000000000e+300
	hx := js_math_high(x)
	ix := hx & 0x7FFFFFFF
	if ix >= 0x7FF00000 {
		return x + x
	}
	if ix < 0x3E300000 {
		if huge + x > js_math_one {
			return x
		}
	}
	mut w := 0.0
	if ix > 0x41B00000 {
		w = js_math_log(js_math_fabs(x)) + ln2
	} else if ix > 0x40000000 {
		t := js_math_fabs(x)
		w = js_math_log(2.0 * t + js_math_one / (math.sqrt(x * x + js_math_one) + t))
	} else {
		t := x * x
		w = js_math_log1p(js_math_fabs(x) + t / (js_math_one + math.sqrt(js_math_one + t)))
	}
	return if hx > 0 { w } else { -w }
}

const js_math_atanhi = [4.63647609000806093515e-01, 7.85398163397448278999e-01,
	9.82793723247329054082e-01, 1.57079632679489655800e+00]
const js_math_atanlo = [2.26987774529616870924e-17, 3.06161699786838301793e-17,
	1.39033110312309984516e-17, 6.12323399573676603587e-17]
const js_math_at = [3.33333333333329318027e-01, -1.99999999998764832476e-01,
	1.42857142725034663711e-01, -1.11111104054623557880e-01, 9.09088713343650656196e-02,
	-7.69187620504482999495e-02, 6.66107313738753120669e-02, -5.83357013379057348645e-02,
	4.97687799461593236017e-02, -3.65315727442169155270e-02, 1.62858201153657823623e-02]

fn js_math_atan(x_ f64) f64 {
	huge := 1.0e300
	mut x := x_
	hx := js_math_high(x)
	ix := hx & 0x7FFFFFFF
	if ix >= 0x44100000 {
		// |x| >= 2^66.
		low := js_math_low(x)
		if ix > 0x7FF00000 || (ix == 0x7FF00000 && low != 0) {
			return x + x
		}
		if hx > 0 {
			return js_math_atanhi[3] + js_math_atanlo[3]
		}
		return -js_math_atanhi[3] - js_math_atanlo[3]
	}
	mut id := 0
	if ix < 0x3FDC0000 {
		// |x| < 0.4375.
		if ix < 0x3E400000 {
			if huge + x > js_math_one {
				return x
			}
		}
		id = -1
	} else {
		x = js_math_fabs(x)
		if ix < 0x3FF30000 {
			if ix < 0x3FE60000 {
				id = 0
				x = (2.0 * x - js_math_one) / (2.0 + x)
			} else {
				id = 1
				x = (x - js_math_one) / (x + js_math_one)
			}
		} else {
			if ix < 0x40038000 {
				id = 2
				x = (x - 1.5) / (js_math_one + 1.5 * x)
			} else {
				id = 3
				x = -1.0 / x
			}
		}
	}
	z := x * x
	w := z * z
	s1 := z * (js_math_at[0] + w * (js_math_at[2] + w * (js_math_at[4] + w * (js_math_at[6] + w * (js_math_at[8] + w * js_math_at[10])))))
	s2 := w * (js_math_at[1] + w * (js_math_at[3] + w * (js_math_at[5] + w * (js_math_at[7] + w * js_math_at[9]))))
	if id < 0 {
		return x - x * (s1 + s2)
	}
	r := js_math_atanhi[id] - ((x * (s1 + s2) - js_math_atanlo[id]) - x)
	return if hx < 0 { -r } else { r }
}

fn js_math_atan2(y f64, x f64) f64 {
	tiny := 1.0e-300
	zero := 0.0
	pi_o_4 := 7.8539816339744827900E-01
	pi_o_2 := 1.5707963267948965580E+00
	pi := 3.1415926535897931160E+00
	pi_lo := 1.2246467991473531772E-16

	hx := js_math_high(x)
	lx := js_math_low(x)
	ix := hx & 0x7FFFFFFF
	hy := js_math_high(y)
	ly := js_math_low(y)
	iy := hy & 0x7FFFFFFF
	if (u32(ix) | ((lx | (u32(0) - lx)) >> 31)) > 0x7FF00000
		|| (u32(iy) | ((ly | (u32(0) - ly)) >> 31)) > 0x7FF00000 {
		// x or y is NaN.
		return x + y
	}
	if ((u32(hx) - u32(0x3FF00000)) | lx) == 0 {
		// x = 1.0.
		return js_math_atan(y)
	}
	// 2 * sign(x) + sign(y).
	mut m := ((hy >> 31) & 1) | ((hx >> 30) & 2)
	if (u32(iy) | ly) == 0 {
		// y = 0.
		return match m {
			0, 1 { y }
			2 { pi + tiny }
			else { -pi - tiny }
		}
	}
	if (u32(ix) | lx) == 0 {
		// x = 0.
		return if hy < 0 { -pi_o_2 - tiny } else { pi_o_2 + tiny }
	}
	if ix == 0x7FF00000 {
		// x is infinite.
		if iy == 0x7FF00000 {
			return match m {
				0 { pi_o_4 + tiny }
				1 { -pi_o_4 - tiny }
				2 { 3.0 * pi_o_4 + tiny }
				else { -3.0 * pi_o_4 - tiny }
			}
		}
		return match m {
			0 { zero }
			1 { -zero }
			2 { pi + tiny }
			else { -pi - tiny }
		}
	}
	if iy == 0x7FF00000 {
		// y is infinite.
		return if hy < 0 { -pi_o_2 - tiny } else { pi_o_2 + tiny }
	}
	// y/x.
	k := (iy - ix) >> 20
	mut z := 0.0
	if k > 60 {
		z = pi_o_2 + 0.5 * pi_lo
		m &= 1
	} else if hx < 0 && k < -60 {
		z = 0.0
	} else {
		z = js_math_atan(js_math_fabs(y / x))
	}
	return match m {
		0 { z }
		1 { -z }
		2 { pi - (z - pi_lo) }
		else { (z - pi_lo) - pi }
	}
}

fn js_math_cos(x f64) f64 {
	ix := js_math_high(x) & 0x7FFFFFFF
	if ix <= 0x3FE921FB {
		return js_math_kernel_cos(x, 0.0)
	}
	if ix >= 0x7FF00000 {
		return x - x
	}
	n, y0, y1 := js_math_rem_pio2(x)
	return match n & 3 {
		0 { js_math_kernel_cos(y0, y1) }
		1 { -js_math_kernel_sin(y0, y1, 1) }
		2 { -js_math_kernel_cos(y0, y1) }
		else { js_math_kernel_sin(y0, y1, 1) }
	}
}

fn js_math_sin(x f64) f64 {
	ix := js_math_high(x) & 0x7FFFFFFF
	if ix <= 0x3FE921FB {
		return js_math_kernel_sin(x, 0.0, 0)
	}
	if ix >= 0x7FF00000 {
		return x - x
	}
	n, y0, y1 := js_math_rem_pio2(x)
	return match n & 3 {
		0 { js_math_kernel_sin(y0, y1, 1) }
		1 { js_math_kernel_cos(y0, y1) }
		2 { -js_math_kernel_sin(y0, y1, 1) }
		else { -js_math_kernel_cos(y0, y1) }
	}
}

fn js_math_tan(x f64) f64 {
	ix := js_math_high(x) & 0x7FFFFFFF
	if ix <= 0x3FE921FB {
		return js_math_kernel_tan(x, 0.0, 1)
	}
	if ix >= 0x7FF00000 {
		return x - x
	}
	n, y0, y1 := js_math_rem_pio2(x)
	// 1 for an even n, -1 for an odd one.
	return js_math_kernel_tan(y0, y1, 1 - int((n & 1) << 1))
}

const js_math_exp_ln2hi = [6.93147180369123816490e-01, -6.93147180369123816490e-01]
const js_math_exp_ln2lo = [1.90821492927058770002e-10, -1.90821492927058770002e-10]
const js_math_exp_half = [0.5, -0.5]

fn js_math_exp(x_ f64) f64 {
	one := 1.0
	o_threshold := 7.09782712893383973096e+02
	u_threshold := -7.45133219101941108420e+02
	invln2 := 1.44269504088896338700e+00
	p1 := 1.66666666666666019037e-01
	p2 := -2.77777777770155933842e-03
	p3 := 6.61375632143793436117e-05
	p4 := -1.65339022054652515390e-06
	p5 := 4.13813679705723846039e-08
	e := 2.718281828459045
	huge := 1.0e+300
	twom1000 := 9.33263618503218878990e-302
	two1023 := 8.988465674311579539e307

	mut x := x_
	mut hi := 0.0
	mut lo := 0.0
	mut k := i32(0)
	mut hx := u32(math.f64_bits(x) >> 32)
	xsb := int((hx >> 31) & 1)
	hx &= 0x7FFFFFFF
	if hx >= 0x40862E42 {
		// |x| >= 709.78...
		if hx >= 0x7FF00000 {
			if ((hx & 0xFFFFF) | js_math_low(x)) != 0 {
				return x + x
			}
			return if xsb == 0 { x } else { 0.0 }
		}
		if x > o_threshold {
			return huge * huge
		}
		if x < u_threshold {
			return twom1000 * twom1000
		}
	}
	if hx > 0x3FD62E42 {
		// |x| > 0.5 ln2.
		if hx < 0x3FF0A2B2 {
			// And |x| < 1.5 ln2.
			if x == 1.0 {
				return e
			}
			hi = x - js_math_exp_ln2hi[xsb]
			lo = js_math_exp_ln2lo[xsb]
			k = i32(1 - xsb - xsb)
		} else {
			k = i32(invln2 * x + js_math_exp_half[xsb])
			t := f64(k)
			hi = x - t * js_math_exp_ln2hi[0]
			lo = t * js_math_exp_ln2lo[0]
		}
		x = hi - lo
	} else if hx < 0x3E300000 {
		// |x| < 2^-28.
		if huge + x > one {
			return one + x
		}
	} else {
		k = 0
	}
	t := x * x
	twopk := if k >= -1021 {
		js_math_words(u32(0x3FF00000) + (u32(k) << 20), 0)
	} else {
		js_math_words(u32(0x3FF00000) + (u32(k + 1000) << 20), 0)
	}
	c := x - t * (p1 + t * (p2 + t * (p3 + t * (p4 + t * p5))))
	if k == 0 {
		return one - ((x * c) / (c - 2.0) - x)
	}
	y := one - ((lo - (x * c) / (2.0 - c)) - hi)
	if k >= -1021 {
		if k == 1024 {
			return y * 2.0 * two1023
		}
		return y * twopk
	}
	return y * twopk * twom1000
}

fn js_math_atanh(x_ f64) f64 {
	one := 1.0
	huge := 1e300
	zero := 0.0
	mut x := x_
	hx := js_math_high(x)
	lx := js_math_low(x)
	ix := hx & 0x7FFFFFFF
	if (u32(ix) | ((lx | (u32(0) - lx)) >> 31)) > 0x3FF00000 {
		// |x| > 1.
		return math.nan()
	}
	if ix == 0x3FF00000 {
		return if x > 0 { math.inf(1) } else { math.inf(-1) }
	}
	if ix < 0x3E300000 && (huge + x) > zero {
		return x
	}
	x = js_math_set_high(x, u32(ix))
	mut t := 0.0
	if ix < 0x3FE00000 {
		// x < 0.5.
		t = x + x
		t = 0.5 * js_math_log1p(t + t * x / (one - x))
	} else {
		t = 0.5 * js_math_log1p((x + x) / (one - x))
	}
	return if hx >= 0 { t } else { -t }
}

const js_math_lg1 = 6.666666666666735130e-01
const js_math_lg2 = 3.999999999940941908e-01
const js_math_lg3 = 2.857142874366239149e-01
const js_math_lg4 = 2.222219843214978396e-01
const js_math_lg5 = 1.818357216161805012e-01
const js_math_lg6 = 1.531383769920937332e-01
const js_math_lg7 = 1.479819860511658591e-01
const js_math_ln2_hi = 6.93147180369123816490e-01
const js_math_ln2_lo = 1.90821492927058770002e-10
const js_math_two54 = 1.80143985094819840000e+16

fn js_math_log(x_ f64) f64 {
	zero := 0.0
	mut x := x_
	mut hx := js_math_high(x)
	lx := js_math_low(x)
	mut k := i32(0)
	if hx < 0x00100000 {
		// x < 2^-1022.
		if (u32(hx & 0x7FFFFFFF) | lx) == 0 {
			return math.inf(-1)
		}
		if hx < 0 {
			return math.nan()
		}
		// A subnormal number: scale it up.
		k -= 54
		x *= js_math_two54
		hx = js_math_high(x)
	}
	if hx >= 0x7FF00000 {
		return x + x
	}
	k += (hx >> 20) - 1023
	hx &= 0x000FFFFF
	mut i := (hx + 0x95F64) & 0x100000
	// Normalize x or x/2.
	x = js_math_set_high(x, u32(hx | (i ^ 0x3FF00000)))
	k += (i >> 20)
	f := x - 1.0
	mut dk := 0.0
	if (0x000FFFFF & (2 + hx)) < 3 {
		// -2^-20 <= f < 2^-20.
		if f == zero {
			if k == 0 {
				return zero
			}
			dk = f64(k)
			return dk * js_math_ln2_hi + dk * js_math_ln2_lo
		}
		r := f * f * (0.5 - 0.33333333333333333 * f)
		if k == 0 {
			return f - r
		}
		dk = f64(k)
		return dk * js_math_ln2_hi - ((r - dk * js_math_ln2_lo) - f)
	}
	s := f / (2.0 + f)
	dk = f64(k)
	z := s * s
	i = hx - 0x6147A
	w := z * z
	j := 0x6B851 - hx
	t1 := w * (js_math_lg2 + w * (js_math_lg4 + w * js_math_lg6))
	t2 := z * (js_math_lg1 + w * (js_math_lg3 + w * (js_math_lg5 + w * js_math_lg7)))
	i |= j
	r := t2 + t1
	if i > 0 {
		hfsq := 0.5 * f * f
		if k == 0 {
			return f - (hfsq - s * (hfsq + r))
		}
		return dk * js_math_ln2_hi - ((hfsq - (s * (hfsq + r) + dk * js_math_ln2_lo)) - f)
	}
	if k == 0 {
		return f - s * (f - r)
	}
	return dk * js_math_ln2_hi - ((s * (f - r) - dk * js_math_ln2_lo) - f)
}

fn js_math_log1p(x f64) f64 {
	zero := 0.0
	lp1 := 6.666666666666735130e-01
	lp2 := 3.999999999940941908e-01
	lp3 := 2.857142874366239149e-01
	lp4 := 2.222219843214978396e-01
	lp5 := 1.818357216161805012e-01
	lp6 := 1.531383769920937332e-01
	lp7 := 1.479819860511658591e-01

	hx := js_math_high(x)
	ax := hx & 0x7FFFFFFF
	mut k := i32(1)
	mut f := 0.0
	mut hu := i32(0)
	mut c := 0.0
	if hx < 0x3FDA827A {
		// 1 + x < sqrt(2)+.
		if ax >= 0x3FF00000 {
			// x <= -1.0.
			if x == -1.0 {
				return math.inf(-1)
			}
			return math.nan()
		}
		if ax < 0x3E200000 {
			// |x| < 2^-29.
			if js_math_two54 + x > zero && ax < 0x3C900000 {
				return x
			}
			return x - x * x * 0.5
		}
		if hx > 0 || hx <= i32(u32(0xBFD2BEC4)) {
			// sqrt(2)/2- <= 1 + x < sqrt(2)+.
			k = 0
			f = x
			hu = 1
		}
	}
	if hx >= 0x7FF00000 {
		return x + x
	}
	if k != 0 {
		mut u := 0.0
		if hx < 0x43400000 {
			u = 1.0 + x
			hu = js_math_high(u)
			k = (hu >> 20) - 1023
			// The correction term.
			c = if k > 0 { 1.0 - (u - x) } else { x - (u - 1.0) }
			c /= u
		} else {
			u = x
			hu = js_math_high(u)
			k = (hu >> 20) - 1023
			c = 0
		}
		hu &= 0x000FFFFF
		if hu < 0x6A09E {
			// Normalize u.
			u = js_math_set_high(u, u32(hu | 0x3FF00000))
		} else {
			// Normalize u/2.
			k += 1
			u = js_math_set_high(u, u32(hu | 0x3FE00000))
			hu = (0x00100000 - hu) >> 2
		}
		f = u - 1.0
	}
	hfsq := 0.5 * f * f
	if hu == 0 {
		// |f| < 2^-20.
		if f == zero {
			if k == 0 {
				return zero
			}
			c += f64(k) * js_math_ln2_lo
			return f64(k) * js_math_ln2_hi + c
		}
		r := hfsq * (1.0 - 0.66666666666666666 * f)
		if k == 0 {
			return f - r
		}
		return f64(k) * js_math_ln2_hi - ((r - (f64(k) * js_math_ln2_lo + c)) - f)
	}
	s := f / (2.0 + f)
	z := s * s
	r := z * (lp1 + z * (lp2 + z * (lp3 + z * (lp4 + z * (lp5 + z * (lp6 + z * lp7))))))
	if k == 0 {
		return f - (hfsq - s * (hfsq + r))
	}
	return f64(k) * js_math_ln2_hi - ((hfsq - (s * (hfsq + r) + (f64(k) * js_math_ln2_lo + c))) - f)
}

// js_math_k_log1p ports k_log1p: log(1+f) - f for 1+f in ~[sqrt(2)/2, sqrt(2)].
fn js_math_k_log1p(f f64) f64 {
	s := f / (2.0 + f)
	z := s * s
	w := z * z
	t1 := w * (js_math_lg2 + w * (js_math_lg4 + w * js_math_lg6))
	t2 := z * (js_math_lg1 + w * (js_math_lg3 + w * (js_math_lg5 + w * js_math_lg7)))
	r := t2 + t1
	hfsq := 0.5 * f * f
	return s * (hfsq + r)
}

fn js_math_log2(x_ f64) f64 {
	ivln2hi := 1.44269504072144627571e+00
	ivln2lo := 1.67517131648865118353e-10
	mut x := x_
	mut hx := js_math_high(x)
	lx := js_math_low(x)
	mut k := i32(0)
	if hx < 0x00100000 {
		// x < 2^-1022.
		if (u32(hx & 0x7FFFFFFF) | lx) == 0 {
			return math.inf(-1)
		}
		if hx < 0 {
			return math.nan()
		}
		k -= 54
		x *= js_math_two54
		hx = js_math_high(x)
	}
	if hx >= 0x7FF00000 {
		return x + x
	}
	if hx == 0x3FF00000 && lx == 0 {
		return 0.0
	}
	k += (hx >> 20) - 1023
	hx &= 0x000FFFFF
	i := (hx + 0x95F64) & 0x100000
	x = js_math_set_high(x, u32(hx | (i ^ 0x3FF00000)))
	k += (i >> 20)
	y := f64(k)
	f := x - 1.0
	hfsq := 0.5 * f * f
	r := js_math_k_log1p(f)
	// f - hfsq in extra precision, and y added in extra precision.
	hi := js_math_set_low(f - hfsq, 0)
	lo := (f - hi) - hfsq + r
	mut val_hi := hi * ivln2hi
	mut val_lo := (lo + hi) * ivln2lo + lo * ivln2hi
	w := y + val_hi
	val_lo += (y - w) + val_hi
	val_hi = w
	return val_lo + val_hi
}

fn js_math_log10(x_ f64) f64 {
	ivln10 := 4.34294481903251816668e-01
	log10_2hi := 3.01029995663611771306e-01
	log10_2lo := 3.69423907715893078616e-13
	mut x := x_
	mut hx := js_math_high(x)
	mut lx := js_math_low(x)
	mut k := i32(0)
	if hx < 0x00100000 {
		// x < 2^-1022.
		if (u32(hx & 0x7FFFFFFF) | lx) == 0 {
			return math.inf(-1)
		}
		if hx < 0 {
			return math.nan()
		}
		k -= 54
		x *= js_math_two54
		hx = js_math_high(x)
		lx = js_math_low(x)
	}
	if hx >= 0x7FF00000 {
		return x + x
	}
	if hx == 0x3FF00000 && lx == 0 {
		return 0.0
	}
	k += (hx >> 20) - 1023
	i := i32((u32(k) & 0x80000000) >> 31)
	hx = (hx & 0x000FFFFF) | ((0x3FF - i) << 20)
	y := f64(k + i)
	x = js_math_set_high(x, u32(hx))
	x = js_math_set_low(x, lx)
	z := y * log10_2lo + ivln10 * js_math_log(x)
	return z + y * log10_2hi
}

fn js_math_expm1(x_ f64) f64 {
	one := 1.0
	tiny := 1.0e-300
	o_threshold := 7.09782712893383973096e+02
	ln2_hi := 6.93147180369123816490e-01
	ln2_lo := 1.90821492927058770002e-10
	invln2 := 1.44269504088896338700e+00
	// Scaled: Qn here is 2^n times the Qn of the method.
	q1 := -3.33333333333331316428e-02
	q2 := 1.58730158725481460165e-03
	q3 := -7.93650757867487942473e-05
	q4 := 4.00821782732936239552e-06
	q5 := -2.01099218183624371326e-07
	huge := 1.0e+300

	mut x := x_
	mut hx := u32(math.f64_bits(x) >> 32)
	xsb := hx & 0x80000000
	hx &= 0x7FFFFFFF
	mut k := i32(0)
	mut c := 0.0
	mut t := 0.0
	mut y := 0.0
	if hx >= 0x4043687A {
		// |x| >= 56*ln2.
		if hx >= 0x40862E42 {
			// |x| >= 709.78...
			if hx >= 0x7FF00000 {
				if ((hx & 0xFFFFF) | js_math_low(x)) != 0 {
					return x + x
				}
				return if xsb == 0 { x } else { -1.0 }
			}
			if x > o_threshold {
				return huge * huge
			}
		}
		if xsb != 0 {
			// x < -56*ln2: -1.
			if x + tiny < 0.0 {
				return tiny - one
			}
		}
	}
	if hx > 0x3FD62E42 {
		// |x| > 0.5 ln2.
		mut hi := 0.0
		mut lo := 0.0
		if hx < 0x3FF0A2B2 {
			// And |x| < 1.5 ln2.
			if xsb == 0 {
				hi = x - ln2_hi
				lo = ln2_lo
				k = 1
			} else {
				hi = x + ln2_hi
				lo = -ln2_lo
				k = -1
			}
		} else {
			k = i32(invln2 * x + (if xsb == 0 { 0.5 } else { -0.5 }))
			t = f64(k)
			hi = x - t * ln2_hi
			lo = t * ln2_lo
		}
		x = hi - lo
		c = (hi - x) - lo
	} else if hx < 0x3C900000 {
		// |x| < 2^-54: x.
		t = huge + x
		return x - (t - (huge + x))
	} else {
		k = 0
	}
	hfx := 0.5 * x
	hxs := x * hfx
	r1 := one + hxs * (q1 + hxs * (q2 + hxs * (q3 + hxs * (q4 + hxs * q5))))
	t = 3.0 - r1 * hfx
	mut e := hxs * ((r1 - t) / (6.0 - x * t))
	if k == 0 {
		return x - (x * e - hxs)
	}
	twopk := js_math_words(u32(0x3FF00000) + (u32(k) << 20), 0)
	e = (x * (e - c) - c)
	e -= hxs
	if k == -1 {
		return 0.5 * (x - e) - 0.5
	}
	if k == 1 {
		if x < -0.25 {
			return -2.0 * (e - (x + 0.5))
		}
		return one + 2.0 * (x - e)
	}
	if k <= -2 || k > 56 {
		y = one - (e - x)
		// V8 writes 2^1023 as this decimal, which is not quite it.
		if k == 1024 {
			y = y * 2.0 * 8.98846567431158e+307
		} else {
			y = y * twopk
		}
		return y - one
	}
	t = one
	if k < 20 {
		// t = 1 - 2^-k.
		t = js_math_set_high(t, u32(0x3FF00000 - (0x200000 >> k)))
		y = t - (e - x)
		y = y * twopk
	} else {
		// t = 2^-k.
		t = js_math_set_high(t, u32((0x3FF - k) << 20))
		y = x - (e + t)
		y += one
		y = y * twopk
	}
	return y
}

fn js_math_cbrt(x f64) f64 {
	b1 := u32(715094163)
	b2 := u32(696219795)
	p0 := 1.87595182427177009643
	p1 := -1.88497979543377169875
	p2 := 1.621429720105354466140
	p3 := -0.758397934778766047437
	p4 := 0.145996192886612446982

	mut hx := js_math_high(x)
	low := js_math_low(x)
	sign := u32(hx) & 0x80000000
	hx = i32(u32(hx) ^ sign)
	if hx >= 0x7FF00000 {
		return x + x
	}
	// A rough cube root to 5 bits from the bits of x.
	mut t := 0.0
	if hx < 0x00100000 {
		// Zero or subnormal.
		if (u32(hx) | low) == 0 {
			return x
		}
		t = js_math_set_high(t, 0x43500000)
		t *= x
		high := u32(math.f64_bits(t) >> 32)
		t = js_math_words(sign | ((high & 0x7FFFFFFF) / 3 + b2), 0)
	} else {
		t = js_math_words(sign | (u32(hx) / 3 + b1), 0)
	}
	// To 23 bits with a polynomial.
	mut r := (t * t) * (t / x)
	t = t * ((p0 + r * (p1 + r * p2)) + ((r * r) * r) * (p3 + r * p4))
	// Rounded away from zero to 23 bits.
	t = math.f64_from_bits((math.f64_bits(t) + 0x80000000) & 0xFFFFFFFFC0000000)
	// One Newton step to 53 bits.
	s := t * t
	r = x / s
	w := t + t
	r = (r - t) / (w + r)
	t = t + t * r
	return t
}

fn js_math_cosh(x f64) f64 {
	kcosh_overflow := 710.4758600739439
	one := 1.0
	half := 0.5
	huge := 1.0e+300
	ix := js_math_high(x) & 0x7FFFFFFF
	if ix < 0x3FD62E43 {
		// |x| in [0, 0.5*log2]: 1 + expm1(|x|)^2 / (2*exp(|x|)).
		t := js_math_expm1(js_math_fabs(x))
		w := one + t
		if ix < 0x3C800000 {
			return w
		}
		return one + (t * t) / (w + w)
	}
	if ix < 0x40360000 {
		// |x| in [0.5*log2, 22].
		t := js_math_exp(js_math_fabs(x))
		return half * t + half / t
	}
	if ix < 0x40862E42 {
		// |x| in [22, log(maxdouble)].
		return half * js_math_exp(js_math_fabs(x))
	}
	if js_math_fabs(x) <= kcosh_overflow {
		w := js_math_exp(half * js_math_fabs(x))
		t := half * w
		return t * w
	}
	if ix >= 0x7FF00000 {
		return x * x
	}
	return huge * huge
}

fn js_math_sinh(x f64) f64 {
	ksinh_overflow := 710.4758600739439
	two_m28 := 3.725290298461914e-9
	log_maxd := 709.7822265625
	shuge := 1.0e307
	h := if x < 0 { -0.5 } else { 0.5 }
	ax := js_math_fabs(x)
	if ax < 22 {
		// |x| in [0, 22]: sign(x) * 0.5 * (E + E/(E+1)).
		if ax < two_m28 {
			return x
		}
		t := js_math_expm1(ax)
		if ax < 1 {
			return h * (2 * t - t * t / (t + 1))
		}
		return h * (t + t / (t + 1))
	}
	if ax < log_maxd {
		return h * js_math_exp(ax)
	}
	if ax <= ksinh_overflow {
		w := js_math_exp(0.5 * ax)
		hw := h * w
		return hw * w
	}
	// Overflow or NaN.
	return x * shuge
}

fn js_math_tanh(x f64) f64 {
	tiny := 1.0e-300
	one := 1.0
	two := 2.0
	huge := 1.0e300
	jx := js_math_high(x)
	ix := jx & 0x7FFFFFFF
	if ix >= 0x7FF00000 {
		// tanh(+-inf) = +-1, tanh(NaN) = NaN.
		if jx >= 0 {
			return one / x + one
		}
		return one / x - one
	}
	mut z := 0.0
	if ix < 0x40360000 {
		// |x| < 22.
		if ix < 0x3E300000 {
			if huge + x > one {
				return x
			}
		}
		if ix >= 0x3FF00000 {
			t := js_math_expm1(two * js_math_fabs(x))
			z = one - two / (t + two)
		} else {
			t := js_math_expm1(-two * js_math_fabs(x))
			z = -t / (t + two)
		}
	} else {
		z = one - tiny
	}
	return if jx >= 0 { z } else { -z }
}

// js_math_float64_max is CSA's Float64Max: NaN when either is.
fn js_math_float64_max(a f64, b f64) f64 {
	if math.is_nan(a) || math.is_nan(b) {
		return math.nan()
	}
	return if a > b { a } else { b }
}

// js_math_hypot ports Math.hypot (src/builtins/math.tq) on the numbers of its arguments: a fast
// path for up to three of them, and Kahan's summation for more.
fn js_math_hypot(values []f64) f64 {
	inf := math.inf(1)
	if values.len == 0 {
		return 0
	}
	if values.len == 1 {
		return js_math_fabs(values[0])
	}
	if values.len == 2 {
		a := js_math_fabs(values[0])
		b := js_math_fabs(values[1])
		if a == inf || b == inf {
			return inf
		}
		max := js_math_float64_max(a, b)
		if math.is_nan(max) {
			return math.nan()
		}
		if max == 0 {
			return 0
		}
		return math.sqrt((a / max) * (a / max) + (b / max) * (b / max)) * max
	}
	if values.len == 3 {
		a := js_math_fabs(values[0])
		b := js_math_fabs(values[1])
		c := js_math_fabs(values[2])
		if a == inf || b == inf || c == inf {
			return inf
		}
		max := js_math_float64_max(js_math_float64_max(a, b), c)
		if math.is_nan(max) {
			return math.nan()
		}
		if max == 0 {
			return 0
		}
		power_a := (a / max) * (a / max)
		power_b := (b / max) * (b / max)
		compensation := (power_a + power_b) - power_a - power_b
		power_c := (c / max) * (c / max) - compensation
		return math.sqrt(power_a + power_b + power_c) * max
	}
	mut abs_values := []f64{len: values.len}
	mut one_is_nan := false
	mut max := 0.0
	for i, value in values {
		if math.is_nan(value) {
			one_is_nan = true
		} else {
			abs_values[i] = js_math_fabs(value)
			if abs_values[i] > max {
				max = abs_values[i]
			}
		}
	}
	if max == inf {
		return inf
	}
	if one_is_nan {
		return math.nan()
	}
	if max == 0 {
		return 0
	}
	mut sum := 0.0
	mut compensation := 0.0
	for value in abs_values {
		n := value / max
		summand := n * n - compensation
		preliminary := sum + summand
		compensation = (preliminary - sum) - summand
		sum = preliminary
	}
	return math.sqrt(sum) * max
}
