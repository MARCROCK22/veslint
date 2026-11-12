// V bug: v3: no prototype for `fn C.f()` when the module links a static library by path (`#flag /path/libfoo.a`)
// Reported in vlang/v#29630.
// expected: 42

#flag @DIR/libext.a

fn C.my_ext_fn() voidptr

fn main() {
	p := C.my_ext_fn()
	println(u64(p))
}
