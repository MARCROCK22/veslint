module rules

import estree
import x.json2

// Helpers of @stylistic/eslint-plugin 5.10.0 (shared/utils of eslint-stylistic) and of ESLint's
// SourceCode that its rules use, on the ESTree and the tokens of typescript-estree.

// sty_same_line ports isTokenOnSameLine(left, right): the end of `left` and the start of `right`
// are on the same line.
fn sty_same_line(t &estree.EsTree, left SourceToken, right SourceToken) bool {
	line_left, _ := t.line_column(left.end)
	line_right, _ := t.line_column(right.start)
	return line_left == line_right
}

// sty_same_line_offsets is isTokenOnSameLine for what ends at `left_end` and starts at
// `right_start`.
fn sty_same_line_offsets(t &estree.EsTree, left_end int, right_start int) bool {
	line_left, _ := t.line_column(left_end)
	line_right, _ := t.line_column(right_start)
	return line_left == line_right
}

// sty_options ports the options of createRule (shared/utils/create-rule.ts): each option given
// replaces the default, an object is merged into an object default (deepMerge).
fn sty_options(options []json2.Any, defaults []json2.Any) []json2.Any {
	count := if options.len > defaults.len { options.len } else { defaults.len }
	mut out := []json2.Any{cap: count}
	for i in 0 .. count {
		if i < options.len && options[i] !is json2.Null {
			given := options[i]
			if i < defaults.len {
				default_value := defaults[i]
				if given is map[string]json2.Any && default_value is map[string]json2.Any {
					out << json2.Any(sty_deep_merge(default_value, given))
					continue
				}
			}
			out << given
			continue
		}
		out << if i < defaults.len { defaults[i] } else { json2.Any(json2.Null{}) }
	}
	return out
}

// sty_deep_merge ports deepMerge of shared/utils/merge.ts: the keys of both, an object merged into
// an object, else the second value.
fn sty_deep_merge(first map[string]json2.Any, second map[string]json2.Any) map[string]json2.Any {
	mut out := map[string]json2.Any{}
	for key, value in first {
		out[key] = value
	}
	for key, value in second {
		if previous := first[key] {
			if previous is map[string]json2.Any && value is map[string]json2.Any {
				out[key] = json2.Any(sty_deep_merge(previous, value))
				continue
			}
		}
		out[key] = value
	}
	return out
}

// sty_option_string is the option at `index` when it is a string, else `fallback`.
fn sty_option_string(options []json2.Any, index int, fallback string) string {
	if index < options.len {
		value := options[index]
		if value is string {
			return value
		}
	}
	return fallback
}

// sty_option_object is the option at `index` when it is an object, else an empty one.
fn sty_option_object(options []json2.Any, index int) map[string]json2.Any {
	if index < options.len {
		value := options[index]
		if value is map[string]json2.Any {
			return value
		}
	}
	return map[string]json2.Any{}
}

// sty_option_bool is `object[key]` when it is a boolean, else none (`undefined` or another value).
fn sty_option_bool(object map[string]json2.Any, key string) ?bool {
	value := object[key] or { return none }
	if value is bool {
		return value
	}
	return none
}
