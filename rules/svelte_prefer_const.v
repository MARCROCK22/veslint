module rules

import json2

// Port of the `svelte/prefer-const` rule of eslint-plugin-svelte 3.24.1: ESLint's prefer-const
// (rules/prefer_const.v), whose meta it has (its defaultOptions too), but for the `let`
// declarations with a declarator whose initializer calls one of `excludedRunes` (default `$props`
// and `$derived`) or a member of one (`$derived.by(…)`). It has no conditions: it lints every file.

struct SvpcOptions {
	core           PconstOptions
	excluded_runes []string
}

// svpc_options reads the options: those of prefer-const and excludedRunes (other properties are
// allowed and ignored).
fn svpc_options(options []json2.Any) !SvpcOptions {
	if options.len == 0 {
		return SvpcOptions{
			excluded_runes: ['\$props', '\$derived']
		}
	}
	first := options[0]
	if first !is map[string]json2.Any {
		return error('the options of `${svelte_prefer_const}` must be an object')
	}
	o := OptionObject{
		rule:   svelte_prefer_const
		values: first.as_map()
	}
	destructuring := o.string_value('destructuring', ['any', 'all'])!
	mut runes := ['\$props', '\$derived']
	if _ := o.values['excludedRunes'] {
		runes = o.string_list('excludedRunes')!
	}
	return SvpcOptions{
		core:           PconstOptions{
			all:                       destructuring == 'all'
			ignore_read_before_assign: o.bool_value('ignoreReadBeforeAssign')!
		}
		excluded_runes: runes
	}
}

fn (mut c Checker) lint_svelte_prefer_const(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	o := svpc_options(c.rule_options(svelte_prefer_const))!
	return c.pconst_lint(root, o.core, o.excluded_runes, mut stats)
}
