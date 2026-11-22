module rules

// `unicorn/prefer-json-parse-buffer` of eslint-plugin-unicorn 79.0.0: a deprecated rule
// (rules/utils/create-deprecated-rules.js), which reports nothing (`create: () => ({})`).

const upjpb_messages = map[string]string{}

fn (mut c Checker) lint_unicorn_prefer_json_parse_buffer(root C.vt_node, abs_path string, mut stats Stats) ![]Finding {
	return []Finding{}
}
