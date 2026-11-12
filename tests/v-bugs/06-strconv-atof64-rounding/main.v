// V bug: strconv: atof64 rounds ties away from zero instead of to even, and misrounds 1e23
// Reported in vlang/v#29632.
// expected: 9007199254740993 9.007199254740992e+15
// expected: 9007199254740995 9.007199254740996e+15
// expected: 9007199254740997 9.007199254740996e+15
// expected: 1e23 1e+23

import strconv

fn main() {
	for s in ['9007199254740993', '9007199254740995', '9007199254740997', '1e23'] {
		x := strconv.atof64(s) or { panic(err) }
		println('${s} ${strconv.ftoa_64(x)}')
	}
}
