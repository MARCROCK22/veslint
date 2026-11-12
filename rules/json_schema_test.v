module rules

import json2
import os

// The cases come from tools/gen_rule_option_cases.mjs: what ESLint itself says of many option
// values of each ported rule, as the options of the rule in a configuration (`config`: the message
// of the error it throws, or null when it takes them) and in the comment
// `/* eslint rule: [severity, ...options] */` (the message it reports); and the same for schemas
// made for the keywords the rules do not exercise. The message of the comment is in `inline` only
// when it is not `config` as ESLint's linter cuts it (the generator checks that for every case).

fn option_cases() map[string]json2.Any {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'rule_option_cases.json')) or {
		panic(err)
	}
	return (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
}

// OptionCase is a case of the file for the rule with that id.
struct OptionCase {
	options  []json2.Any
	severity json2.Any // as the comment has it
	comment  string    // the text of the comment after `eslint`
	config   string    // ESLint's messages; '' when it takes the options
	inline   string
}

fn option_case(id string, item json2.Any) OptionCase {
	entry := item.as_map()
	options := entry['options'] or { panic('no options') }.as_array()
	severity := entry['severity'] or { json2.Any(2) }
	mut value := [severity]
	for option in options {
		value << option
	}
	config := entry['config'] or { panic('no config') }
	expected_config := if config is string { config } else { '' }
	prefix := 'Key "rules": Key "${id}":'
	assert expected_config == '' || expected_config.starts_with(prefix)
	mut expected_inline := if expected_config == '' {
		''
	} else {
		'Inline configuration for rule "${id}" is invalid:\n\t${js_trim(expected_config[prefix.len..])}\n'
	}
	if inline := entry['inline'] {
		expected_inline = if inline is string { inline } else { '' }
	}
	return OptionCase{
		options:  options
		severity: severity
		comment:  '${id}: ${js_json_stringify(json2.Any(value))}'
		config:   expected_config
		inline:   expected_inline
	}
}

// first_differences keeps a failure readable: the first few, and how many there are.
fn first_differences(wrong []string) string {
	if wrong.len == 0 {
		return ''
	}
	return '${wrong.len} differences; the first ones:\n' + wrong#[..5].join('\n')
}

// rule_schemas.v has the schemas ESLint has for the ported rules and the default options of its
// rules and typescript-eslint's, with the properties in the same order.
fn test_rule_schemas_are_those_of_eslint() {
	data := option_cases()
	schemas := data['schemas'] or { panic('no schemas') }.as_map()
	assert schemas.len == names.len
	assert rule_option_schemas.len == names.len
	for name in names {
		table := json2.decode[json2.Any](rule_option_schemas[name] or { panic('no schema of ${name}') }) or {
			panic(err)
		}
		// The cases name the typescript-eslint rules without their prefix.
		assert js_json_stringify(table) == js_json_stringify(schemas[name.all_after(typescript_eslint_prefix)] or {
			panic('ESLint has no schema of ${name}')
		}), name
	}
	defaults := data['ruleDefaults'] or { panic('no ruleDefaults') }.as_map()
	assert eslint_rule_default_options.len == defaults.len
	assert defaults.len > 100
	for id, value in defaults {
		assert js_json_stringify(json2.Any(eslint_default_options(id))) == js_json_stringify(value), id
	}
}

// The options of every case, for a rule that is on, give the text of ESLint's error for a
// configuration; and the comment of every case, read and applied as the comments of a file are,
// the message ESLint reports for it.
fn test_rule_options_are_validated_like_eslint() {
	data := option_cases()
	mut checked := 0
	mut rejected := 0
	mut wrong := []string{}
	for group in data['rules'] or { panic('no rules') }.as_array() {
		name := group.as_map()['rule'] or { panic('no rule') }.str()
		// The cases name the typescript-eslint rules without their prefix (the others by their id);
		// veslint, by their id.
		id := if name.contains('/') { name } else { typescript_eslint_prefix + name }
		for item in group.as_map()['cases'] or { panic('no cases') }.as_array() {
			case := option_case(id, item)
			// ESLint does not validate the options of a rule a configuration turns off.
			problems := if rule_severity_of(case.severity) == 0 {
				''
			} else {
				rule_options_problems(id, case.options)
			}
			config := if problems == '' { '' } else { 'Key "rules": Key "${id}":\n${problems}' }
			if config != case.config {
				wrong << '${case.comment} in a configuration:\n  got ${json2.encode(config)}\n  ESLint gives ${json2.encode(case.config)}'
			}
			label, value, _ := parse_directive(' eslint ${case.comment} ') or {
				panic(case.comment)
			}
			assert label == 'eslint'
			mut checker := Checker{}
			mut result := InlineConfig{
				comments: [DirectiveComment{
					label: label
					value: value
				}]
			}
			checker.apply_inline_rules(mut result, LintConfig{})
			inline := if result.problems.len == 0 { '' } else { result.problems[0].text }
			if inline != case.inline || result.problems.len > 1 {
				wrong << '/* eslint ${case.comment} */:\n  got ${json2.encode(inline)}\n  ESLint gives ${json2.encode(case.inline)}'
			}
			checked++
			if case.inline != '' {
				rejected++
			}
		}
	}
	assert first_differences(wrong) == ''
	assert checked >= 4000
	assert rejected >= 2500
}

// The validator itself, on schemas with the keywords and the combinations the rules do not have.
fn test_schemas_are_validated_like_ajv() {
	data := option_cases()
	mut checked := 0
	mut rejected := 0
	mut wrong := []string{}
	for group in data['synthetic'] or { panic('no synthetic') }.as_array() {
		name := group.as_map()['name'] or { panic('no name') }.str()
		id := 'synthetic/${name}'
		schema := group.as_map()['schema'] or { panic('no schema') }
		for item in group.as_map()['cases'] or { panic('no cases') }.as_array() {
			case := option_case(id, item)
			severity := rule_severity_of(case.severity)
			problems := schema_problem_lines(schema, json2.Any(case.options))
			config := if problems == '' || severity == 0 {
				''
			} else {
				'Key "rules": Key "${id}":\n${problems}'
			}
			if config != case.config {
				wrong << '${case.comment} in a configuration:\n  got ${json2.encode(config)}\n  ESLint gives ${json2.encode(case.config)}'
			}
			// In a comment the options are the ones ESLint's parser reads from it, and only the
			// number 0 goes without validation.
			_, values := parse_inline_rules(case.comment) or { panic(case.comment) }
			read := values[0].as_array()
			inline_problems := schema_problem_lines(schema, json2.Any(read[1..]))
			inline := if inline_problems == '' || (json_is_number(read[0]) && severity == 0) {
				''
			} else {
				'Inline configuration for rule "${id}" is invalid:\n\t${js_trim(inline_problems)}\n'
			}
			if inline != case.inline {
				wrong << '/* eslint ${case.comment} */:\n  got ${json2.encode(inline)}\n  ESLint gives ${json2.encode(case.inline)}'
			}
			checked++
			if case.inline != '' {
				rejected++
			}
		}
	}
	assert first_differences(wrong) == ''
	assert checked >= 2000
	assert rejected >= 1000
}

// A pattern that is not a regular expression fits the schema (a string): in ESLint the rule
// throws when it starts; veslint says so in the place of the comment.
fn test_inline_options_veslint_cannot_take() {
	mut checker := Checker{}
	mut result := InlineConfig{
		comments: [
			DirectiveComment{
				label: 'eslint'
				value: '@typescript-eslint/dot-notation: [2, {"allowPattern": "("}]'
			},
		]
	}
	checker.apply_inline_rules(mut result, LintConfig{})
	assert result.problems.len == 1
	assert result.problems[0].text.starts_with('Inline configuration for rule "@typescript-eslint/dot-notation" is invalid:\n\t`@typescript-eslint/dot-notation`: option `allowPattern`')
	// Turned off, the rule never starts.
	mut off := InlineConfig{
		comments: [
			DirectiveComment{
				label: 'eslint'
				value: '@typescript-eslint/dot-notation: ["off", {"allowPattern": "("}]'
			},
		]
	}
	checker.apply_inline_rules(mut off, LintConfig{})
	assert off.problems.len == 0
}

fn test_json_for_error() {
	value := json2.decode[json2.Any]('{"a": [1, {"b": null}, []], "c": {}, "10": "x\\ny"}') or {
		panic(err)
	}
	assert json_for_error(value, true, 4) == '{\n        "10": "x\\ny",\n        "a": [\n            1,\n            {\n                "b": null\n            },\n            []\n        ],\n        "c": {}\n    }'
	assert json_for_error(json2.Any(''), true, 4) == ''
	assert json_for_error(json2.Any(f64(0)), true, 4) == '0'
	assert json_for_error(json2.Any(false), true, 4) == 'false'
	assert json_for_error(json2.Any(json2.null), true, 8) == 'null'
	assert json_for_error(json2.Any(json2.null), false, 4) == 'undefined'
	assert json_for_error(json2.Any('x'), true, 4) == '"x"'
}
