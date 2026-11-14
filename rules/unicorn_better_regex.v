module rules

// `unicorn/better-regex` of eslint-plugin-unicorn 79.0.0: a deprecated rule, "Removed. Prefer
// `eslint-plugin-regexp`" (index.js, rules/utils/create-deprecated-rules.js), which reports nothing
// (`create: () => ({})`).

const ubr_messages = map[string]string{}

fn (mut c Checker) lint_unicorn_better_regex(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	return []Finding{}
}
