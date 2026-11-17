module rules

const ccase_messages = {
	'notCamelCase': "Identifier '{{name}}' is not in camel case."
}
const solb_messages = {
	'x': 'x'
}
const sabn_messages = {
	'x': 'x'
}
const saen_messages = {
	'x': 'x'
}
const vncon_messages = {
	'unexpected': 'Unexpected console statement.'
}

fn (mut c Checker) vue_wrap_no_console_base(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return []
}

fn (mut c Checker) lint_camelcase_base(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return []
}

fn (mut c Checker) lint_stylistic_operator_linebreak(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return []
}

fn (mut c Checker) lint_stylistic_array_bracket_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return []
}

fn (mut c Checker) lint_stylistic_array_element_newline(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return []
}
