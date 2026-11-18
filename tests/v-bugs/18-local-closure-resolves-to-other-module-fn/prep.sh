# Creates the module whose private `blank` the closure of main.v is resolved to.
mkdir -p a
cat > a/a.v <<'V'
module a

fn blank(src string, ranges [][]int) string {
	return src
}

pub fn use_a() string {
	return blank('x', [][]int{})
}
V
touch v.mod
