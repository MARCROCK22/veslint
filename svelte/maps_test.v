module svelte

fn test_virtual_maps_script_and_template() {
	src := '<script lang="ts">\n  let count = \$state(0);\n</script>\n<p>{count}</p>\n'
	mut doc := parse_svelte(src) or { panic(err) }
	defer {
		doc.free()
	}
	assert doc.error == none
	// `count` of the script and of the template are where the virtual code has them.
	script_at := src.index('count') or { panic('') }
	v := doc.file_to_virtual(script_at)
	assert v >= 0
	assert doc.virtual_code[v..v + 5] == 'count'
	assert doc.virtual_to_file(v, false) == script_at
	tpl_at := src.index('{count}') or { panic('') } + 1
	vt := doc.file_to_virtual(tpl_at)
	assert vt >= 0
	assert doc.virtual_code[vt..vt + 5] == 'count'
	assert doc.virtual_to_file(vt, false) == tpl_at
	// Markup is not in the virtual code.
	assert doc.file_to_virtual(src.index('<p>') or { panic('') } + 1) < 0
}
