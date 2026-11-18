module svelte_compiler

import svelte

// compile_codes compiles a component as eslint-plugin-svelte's compile() call would (raw source,
// no transformation): its warning codes, or `error:<code>`.
fn compile_codes(src string) []string {
	doc := svelte.parse_svelte(src) or { return ['parse failed'] }
	defer {
		unsafe { doc.free() }
	}
	c := build_component(doc, false) or {
		if err is CompileError {
			return ['error:${err.diag.code}']
		}
		return ['build failed']
	}
	r := analyze(c, Options{})
	if e := r.error {
		return ['error:${e.diag.code}']
	}
	return r.warnings.map(it.code)
}

fn test_a11y_and_ignore() {
	assert compile_codes('<img src="x" />') == ['a11y_missing_attribute']
	assert compile_codes('<!-- svelte-ignore a11y_missing_attribute -->\n<img src="x" />') == []
	assert compile_codes('<div onclick={() => {}}></div>') == [
		'a11y_click_events_have_key_events',
		'a11y_no_static_element_interactions',
	]
}

fn test_runes() {
	assert compile_codes('<script>\n\tlet { a } = \$props();\n\tconsole.log(a);\n</script>') == [
		'state_referenced_locally',
	]
	assert compile_codes('<script>\n\tlet n = 0;\n\tlet d = \$derived(n);\n\tn = 1;\n</script>\n{n}{d}') == [
		'non_reactive_update',
	]
	assert compile_codes('<script>\n\tlet x = \$state(1);\n\tx = \$state(2);\n</script>') == [
		'error:state_invalid_placement',
	]
}

fn test_legacy() {
	assert compile_codes('<script>\n\texport let a;\n</script>') == ['export_let_unused']
	assert compile_codes('<script>\n\tlet x = 1;\n\tlet x = 2;\n</script>') == [
		'error:js_parse_error',
	]
}

fn test_css() {
	assert compile_codes('<div class="a"></div>\n<style>\n\t.a { color: red; }\n\t.b { color: blue; }\n</style>') == [
		'css_unused_selector',
	]
	assert compile_codes('<div></div>\n<style>\n\t.a {\n</style>') == ['error:unexpected_eof']
}
