module rules

// `unicorn/no-hex-escape` of eslint-plugin-unicorn 79.0.0: a deprecated rule, "Replaced by
// `unicorn/prefer-literal-ascii` and `unicorn/prefer-unicode-code-point-escapes`, which cover more
// cases." (rules/utils/create-deprecated-rules.js), which reports nothing (`create: () => ({})`).

const unhe_messages = map[string]string{}

fn (mut c Checker) lint_unicorn_no_hex_escape(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	return []Finding{}
}
