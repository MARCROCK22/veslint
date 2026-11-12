module main

import json2
import os
import rules

// `--config` configuration: the `rules` section of an ESLint configuration, or the output of
// `eslint --print-config`.

const typescript_eslint_prefix = rules.typescript_eslint_prefix

// RuleConfig is a rule that veslint applies, with its effective options (the configured ones
// merged with the defaults). Findings of a rule set to "warn" are printed but do not change the
// exit code, as in ESLint.
struct RuleConfig {
	name    string
	error   bool
	options []json2.Any
}

// RuleSetup holds the rules veslint takes from the configuration, and the active rules it does
// not have, to warn about them.
struct RuleSetup {
	rules   []RuleConfig // in the order of rules.names
	ignored []string
	// The effective options of every ported rule the configuration mentions, also the ones it
	// turns off (an inline `/* eslint rule: "error" */` takes them).
	base_options map[string][]json2.Any
	// What ESLint says of the options of a ported rule that is off, when they do not fit it and a
	// comment turns the rule on.
	off_problems map[string]string
}

fn load_config(path string) !RuleSetup {
	text := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	root := json2.decode[json2.Any](text) or {
		return error('${path}: not valid JSON (${err.msg()})')
	}
	if root !is map[string]json2.Any {
		return error('${path}: expected an object with a `rules` section')
	}
	section := root.as_map()['rules'] or { return error('${path}: missing `rules` section') }
	if section !is map[string]json2.Any {
		return error('${path}: `rules` must be an object')
	}
	return rule_setup(section.as_map(), path)!
}

// rule_setup reads the `rules` section. A key is a rule of veslint only as its full ESLint id
// (`@typescript-eslint/await-thenable`), as ESLint names it: an id without a plugin is a rule of
// ESLint core.
// What does not fit is an error with ESLint's own text, in ESLint's order: first the value of
// every rule (rulesSchema.validate of flat-config-schema.js), then the options of the rules that
// are on against their schemas (Config.validateRulesConfig).
fn rule_setup(section map[string]json2.Any, path string) !RuleSetup {
	mut severities := map[string]int{}
	mut options := map[string][]json2.Any{}
	for key, value in section {
		severities[key], options[key] = rule_severity(key, value, path)!
	}
	mut ignored := []string{}
	for key, _ in section {
		if key !in rules.names && severities[key] > 0 {
			ignored << key
		}
	}
	for key, _ in section {
		if severities[key] == 0 || key !in rules.names {
			continue
		}
		problems := rules.rule_options_problems(key, options[key])
		if problems != '' {
			return error('${path}: Key "rules": Key "${key}":\n${problems}')
		}
	}
	mut active := []RuleConfig{}
	mut base_options := map[string][]json2.Any{}
	mut off_problems := map[string]string{}
	for name in rules.names {
		if name !in section {
			continue
		}
		key := name
		if severities[key] == 0 {
			// ESLint does not validate the options of a rule that is off, until a configuration
			// comment turns it on.
			reason := rules.rule_options_inline_reason(name, options[key])
			if reason != '' {
				off_problems[name] = reason
			} else if effective := rules.effective_options(name, options[key]) {
				base_options[name] = effective
			} else {
				off_problems[name] = err.msg()
			}
			continue
		}
		effective := check_options(name, options[key], path)!
		base_options[name] = effective
		active << RuleConfig{
			name:    name
			error:   severities[key] == 2
			options: effective
		}
	}
	return RuleSetup{
		rules:        active
		ignored:      ignored
		base_options: base_options
		off_problems: off_problems
	}
}

// rule_severity reads the value of an ESLint rule: the severity (0 = off, 1 = warn, 2 = error, as
// a number or as text), alone or as the first element of an array whose rest are the options. A
// value that is none of that is an error with the text ESLint prints for it: assertIsRuleOptions
// and assertIsRuleSeverity of flat-config-schema.js, with messages/invalid-rule-options.js and
// messages/invalid-rule-severity.js.
fn rule_severity(key string, value json2.Any, path string) !(int, []json2.Any) {
	if value !is string && value !is []json2.Any && !rules.json_is_number(value) {
		given := rules.json_for_error(value, true, 4)
		suggested := rules.json_for_error(value, true, 8)
		return error('${path}: Configuration for rule "${key}" is invalid. Each rule must have a severity ("off", 0, "warn", 1, "error", or 2) and may be followed by additional options for the rule.\n\nYou passed \'${given}\', which doesn\'t contain a valid severity.\n\nIf you\'re attempting to configure rule options, perhaps you meant:\n\n    "${key}": ["error", ${suggested}]\n\nSee https://eslint.org/docs/latest/use/configure/rules#use-configuration-files for configuring rules.\n')
	}
	mut level := value
	mut has_level := true
	mut options := []json2.Any{}
	if value is []json2.Any {
		has_level = value.len > 0
		if has_level {
			level = value[0]
			options = value[1..].clone()
		}
	}
	severity := if has_level { rules.rule_severity_of(level) } else { -1 }
	if severity < 0 {
		given := rules.json_for_error(level, has_level, 4)
		return error('${path}: Configuration for rule "${key}" is invalid. Expected severity of "off", 0, "warn", 1, "error", or 2.\n\nYou passed \'${given}\'.\n\nSee https://eslint.org/docs/latest/use/configure/rules#use-configuration-files for configuring rules.\n')
	}
	return severity, options
}

// check_options merges the options of a rule with its defaults and checks them; the error names
// the configuration file.
fn check_options(name string, options []json2.Any, path string) ![]json2.Any {
	return rules.effective_options(name, options) or { return error('${path}: ${err.msg()}') }
}
