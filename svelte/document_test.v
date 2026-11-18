module svelte

fn test_parse_small() {
	mut doc := parse_svelte('<script lang="ts">\n  let n = 1;\n</script>\n{#if n}<b {n}>{n}</b>{/if}\n') or {
		panic(err)
	}
	defer {
		doc.free()
	}
	assert doc.error == none
	assert doc.nodes[0].children.len == 3
}
