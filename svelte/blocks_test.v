module svelte

fn test_extract_empty_script() {
	sc := split_document('<script lang="javascript"></script>\n\n<style lang="scss"></style>\n')
	assert sc.blocks.len == 2
	assert sc.blocks[0].content_s == 26
	assert sc.blocks[0].content_e == 26
	assert sc.blocks[0].attrs.len == 1
}

fn test_script_attrs_converted() {
	mut doc := parse_svelte('<script lang="javascript"></script>\n\n<style lang="scss"></style>\n') or {
		panic(err)
	}
	st := doc.nodes[doc.nodes[0].children[0]].start_tag
	assert doc.nodes[st].attributes.len == 1
}
