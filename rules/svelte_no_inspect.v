module rules

// Port of the `svelte/no-inspect` rule of eslint-plugin-svelte 3.24.1: every Identifier `$inspect`
// is reported, in a component in runes mode or a `.svelte.[js|ts]` module (its condition: Svelte 5,
// runes true or undetermined; another file's runes are null).

const svnin_messages = {
	'unexpected': 'Do not use $inspect directive'
}

fn (mut c Checker) lint_svelte_no_inspect(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	if !c.svsc_runes_on(abs_path) {
		return []
	}
	e := c.svsc_es(root, abs_path) or { return [] }
	t := e.t
	mut findings := []Finding{}
	for i in e.entered() {
		if t.typ(i) == .identifier && (t.string_of(i, .name) or { '' }) == '\$inspect' {
			findings << c.svsc_report(&e, i, 'unexpected', {})
		}
	}
	return findings
}
