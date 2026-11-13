module rules

import json2
import jsregexp
import offsets
import treesitter { Ident, node_end, node_start, nodes_of_kind, position_of }

// The comments that configure ESLint, like ESLint 10.6.0 applies them (its JS language's
// getInlineConfigNodes, applyInlineConfig and getDisableDirectives, @eslint/plugin-kit's
// ConfigCommentParser and lib/linter/apply-disable-directives.js):
//   - `/* eslint rule: value */` changes the rules of the file;
//   - `eslint-disable`, `eslint-enable`, `eslint-disable-line` and `eslint-disable-next-line`
//     suppress findings, and the ones that suppress nothing are reported;
//   - `/* global */` gives the file globals and `/* exported */` marks globals as used (see
//     ScopeSetup in scope.v); `/* eslint-env */` is no longer supported by ESLint.
// The problems ESLint reports about those comments are findings of `problem_rule` (or of the rule
// that does not exist), with their message in `text`.
// The options of a configuration comment are validated against the schema of the rule, with
// ESLint's own words (json_schema.v); the ones of a rule veslint does not have are not, since only
// that rule has its schema.
// Deviation: whether a directive that names a rule veslint does not have is unused cannot be
// known, so it is never reported (see LintConfig.other_active).

const directive_labels = ['eslint-disable-next-line', 'eslint-disable-line', 'eslint-disable',
	'eslint-enable', 'eslint-env', 'eslint', 'exported', 'globals', 'global']

// DirectiveComment is a comment that configures ESLint.
struct DirectiveComment {
	label         string
	value         string // what follows the label, without the justification
	justification string
	start         int // bytes
	end           int
	at            Ident
	line          int // of its start: 1-based, and the column in UTF-16 units like ESLint's messages
	column        int
	end_line      int
	end_column    int
mut:
	rule_ids []string // of a disable or enable directive
}

// DisableDirective is one rule of a disable or enable comment (createDisableDirectives): `rule` is
// the ESLint rule id, and without has_rule the directive is for every rule.
struct DisableDirective {
	kind     string // 'disable', 'enable', 'disable-line' or 'disable-next-line'
	line     int
	column   int
	rule     string
	has_rule bool
	comment  int // index of its comment
}

// DirectiveEntry is a directive as applyDisableDirectives applies it: a line directive becomes a
// `disable` at its line and an `enable` at the next one.
struct DirectiveEntry {
	disable  bool
	line     int
	column   int
	rule     string
	has_rule bool
	source   int // index of its DisableDirective
	order    int // to keep the sort stable
}

// InlineConfig is what the comments of a file ask for.
struct InlineConfig {
mut:
	rules        []RuleSetting // the rules of the file, in the order of `names`
	other_active []string      // rules veslint does not have that a comment turns on
	other_off    []string      // and the ones a comment turns off
	problems     []Finding
	comments     []DirectiveComment
	directives   []DisableDirective
	// globals are the values the `/* global */` comments give: 'readonly', 'writable' or 'off';
	// exported, the names of the `/* exported */` comments.
	globals  map[string]string
	exported []string
	// lines are the lines of the file as ESLint counts them (the `loc` of its comments and
	// problems), which is where a directive of one line or of the next one applies.
	lines offsets.LineStarts
}

// line_column is ESLint's position of a byte offset in a message: 1-based line and column, the
// column in UTF-16 units.
fn (c &Checker) line_column(lines offsets.LineStarts, offset int) (int, int) {
	return lines.line_index(offset) + 1, utf16_column(c.src, offset) + 1
}

// finding_line is ESLint's line of a problem: 1-based, and 0 for a report without a place in the
// file (a negative row, see offsets.utf16_positions).
fn finding_line(lines offsets.LineStarts, f Finding) int {
	return if f.stmt.row < 0 { 0 } else { lines.line_index(f.stmt.start_byte) + 1 }
}

// directive_problem is a problem about a comment: `level` is fatal, error or warning, and `rule`
// the id of a rule that does not exist, or problem_rule.
fn directive_problem(comment DirectiveComment, level string, rule string, text string) Finding {
	return Finding{
		stmt:       comment.at
		rule:       rule
		message_id: level
		severity:   if level == 'warning' { 1 } else { 2 }
		text:       text
	}
}

// parse_directive ports ConfigCommentParser.parseDirective: the label, the value and the
// justification (what follows ` -- `) of the text of a comment; none when it is not a directive.
fn parse_directive(value string) ?(string, string, string) {
	runes := value.runes()
	mut directive := runes.clone()
	mut justification := []rune{}
	// /\s-{2,}\s/u
	for i in 0 .. runes.len {
		if !is_js_space(runes[i]) {
			continue
		}
		mut j := i + 1
		for j < runes.len && runes[j] == `-` {
			j++
		}
		if j - i > 2 && j < runes.len && is_js_space(runes[j]) {
			directive = runes[..i].clone()
			justification = runes[j + 1..].clone()
			break
		}
	}
	text := js_trim(directive.string())
	for label in directive_labels {
		if !text.starts_with(label) {
			continue
		}
		rest := text[label.len..]
		if rest == '' || is_js_space(rest.runes()[0]) {
			return label, js_trim(rest), js_trim(justification.string())
		}
	}
	return none
}

// parse_list_config ports parseListConfig: names separated by commas, each one trimmed and
// without its quotes.
fn parse_list_config(value string) []string {
	mut out := []string{}
	for part in value.split(',') {
		mut name := js_trim(part)
		if name.len >= 2 && name[0] in [`'`, `"`] && name[name.len - 1] == name[0] {
			name = name[1..name.len - 1]
		}
		if name != '' && name !in out {
			out << name
		}
	}
	return out
}

// inline_config reads the comments of the file: the rules they leave for it, the disable
// directives and the problems of the comments themselves.
fn (mut c Checker) inline_config(root C.TSNode, config LintConfig) InlineConfig {
	mut result := InlineConfig{
		rules: config.rules.clone()
		lines: offsets.line_starts(c.src)
	}
	for node in c.nodes_of_kind(root, c'comment') {
		text := c.text(node)
		is_line := text.starts_with('//')
		if !is_line && (text.len < 4 || !text.ends_with('*/')) {
			continue
		}
		value := if is_line { text[2..] } else { text[2..text.len - 2] }
		label, directive_value, justification := parse_directive(value) or { continue }
		if is_line && label !in ['eslint-disable-line', 'eslint-disable-next-line'] {
			continue
		}
		line, column := c.line_column(result.lines, node_start(node))
		end_line, end_column := c.line_column(result.lines, node_end(node))
		result.comments << DirectiveComment{
			label:         label
			value:         directive_value
			justification: justification
			start:         node_start(node)
			end:           node_end(node)
			at:            position_of(node)
			line:          line
			column:        column
			end_line:      end_line
			end_column:    end_column
		}
	}
	if result.comments.len == 0 {
		return result
	}
	if config.no_inline_config {
		for comment in result.comments {
			result.problems << directive_problem(comment, 'warning', problem_rule, "'${c.src[comment.start..comment.end]}' has no effect because you have 'noInlineConfig' setting in your config.")
		}
		result.comments = []DirectiveComment{}
		return result
	}
	c.apply_inline_rules(mut result, config)
	collect_disable_directives(mut result, config)
	return result
}

// apply_inline_rules ports the part of applyInlineConfig and of the linter that handles
// `/* eslint … */`, `/* global … */`, `/* exported … */` and `/* eslint-env … */`.
fn (mut c Checker) apply_inline_rules(mut result InlineConfig, config LintConfig) {
	mut settings := map[string]RuleSetting{}
	for setting in config.rules {
		settings[setting.name] = setting
	}
	mut configured := []string{} // rule ids a previous comment configured
	for comment in result.comments {
		match comment.label {
			'eslint-env' {
				result.problems << directive_problem(comment, 'fatal', problem_rule, '/* eslint-env */ comments are no longer supported.')
			}
			'exported' {
				result.exported << exported_names(comment.value)
			}
			'global', 'globals' {
				for entry in global_entries(comment.value) {
					// normalizeConfigGlobal: a name without a value is read-only.
					value := if !entry.has_value {
						'readonly'
					} else {
						match entry.value {
							'off' { 'off' }
							'true', 'writeable', 'writable' { 'writable' }
							'false', 'readable', 'readonly' { 'readonly' }
							else { '' }
						}
					}
					if value == '' {
						result.problems << directive_problem(comment, 'fatal', problem_rule,
							"'${entry.value}' is not a valid configuration for a global (use 'readonly', 'writable', or 'off')")
						continue
					}
					result.globals[entry.name] = value
				}
			}
			'eslint' {
				ids, values := parse_inline_rules(comment.value) or {
					result.problems << directive_problem(comment, 'fatal', problem_rule,
						err.msg())
					continue
				}
				for i, id in ids {
					if !config.rule_exists(id) {
						result.problems << directive_problem(comment, 'error', id, "Definition for rule '${id}' was not found.")
						continue
					}
					if id in configured {
						result.problems << directive_problem(comment, 'error', problem_rule,
							'Rule "${id}" is already configured by another configuration comment in the preceding code. This configuration is ignored.')
						continue
					}
					items := if values[i] is []json2.Any {
						values[i].as_array()
					} else {
						[values[i]]
					}
					severity := if items.len > 0 { inline_severity(items[0]) } else { -1 }
					if severity < 0 {
						result.problems << directive_problem(comment, 'error', id, 'Inline configuration for rule "${id}" is invalid:\n\tExpected severity of "off", 0, "warn", 1, "error", or 2. You passed "${js_string_of_json(values[i])}".\n')
						continue
					}
					if config.report_unused_inline != 0 {
						unused := unused_inline_config(id, items, config)
						if unused != '' {
							result.problems << directive_problem(comment, if config.report_unused_inline == 1 {
								'warning'
							} else {
								'error'
							}, problem_rule, unused)
						}
					}
					name := id
					if name !in names {
						// A rule veslint does not have: only its state is known.
						configured << id
						if severity > 0 && id !in result.other_active {
							result.other_active << id
						} else if severity == 0 {
							result.other_off << id
						}
						continue
					}
					// With only a severity, the options are those of the configuration, which ESLint
					// validates here when the configuration has the rule off. The options of any other
					// comment go over the default ones of the rule's meta and are validated against
					// its schema.
					mut options := []json2.Any{}
					mut reason := ''
					if items.len == 1 && name in config.base_options {
						options = config.base_options[name].clone()
					} else if items.len == 1 && name in config.off_problems {
						reason = config.off_problems[name]
					} else {
						reason = js_trim(rule_options_problems(name, items[1..]))
						if reason == '' && severity > 0 {
							// What veslint itself cannot take (a pattern that is not a regular
							// expression, which makes the rule throw in ESLint).
							options = effective_options(name, items[1..]) or {
								reason = err.msg()
								[]json2.Any{}
							}
						}
					}
					// validateRulesConfig skips a rule whose severity is the number 0 ("off" is not).
					if reason != '' && !(json_kind(items[0]) == .number && json_number(items[0]) == 0) {
						result.problems << directive_problem(comment, 'error', id, 'Inline configuration for rule "${id}" is invalid:\n\t${reason}\n')
						continue
					}
					configured << id
					if severity == 0 {
						settings.delete(name)
					} else {
						settings[name] = RuleSetting{
							name:     name
							severity: severity
							options:  options
						}
					}
				}
			}
			else {}
		}
	}
	result.rules = []RuleSetting{}
	for name in names {
		if setting := settings[name] {
			result.rules << setting
		}
	}
}

// unused_inline_config ports addProblemIfSameSeverityAndOptions of ESLint's linter with the
// options the linter gives it: the message for a rule that a configuration comment configures
// like the configuration already does (reportUnusedInlineConfigs), or '' if it changes something.
// `items` is the value of the comment as an array, with a valid severity first.
fn unused_inline_config(id string, items []json2.Any, config LintConfig) string {
	has_existing := id in config.all_rules
	existing := if has_existing {
		value := config.all_rules[id] or { json2.Any('off') }
		if value is []json2.Any { value.as_array() } else { [value] }
	} else {
		[json2.Any('off')]
	}
	if existing.len == 0 {
		return ''
	}
	// A comment with only a severity keeps the options of the configuration; any other gets the
	// default options of the rule under its own. (An array of json2.Any is a json2.Any too: `<<`
	// would add it as one element.)
	mut options := items.clone()
	if items.len == 1 && has_existing {
		options = [items[0]]
		for option in existing[1..] {
			options << option
		}
	} else {
		merged := deep_merge_arrays(config.default_options_of(id), items[1..])
		if merged.len > 0 {
			options = [items[0]]
			for option in merged {
				options << option
			}
		}
	}
	severity := inline_severity(existing[0])
	if severity < 0 || severity != inline_severity(options[0]) {
		return ''
	}
	already := if has_existing {
		"is already configured to '${['off', 'warn', 'error'][severity]}'"
	} else {
		"is not enabled so can't be turned off"
	}
	if (existing.len == 1 && options.len == 1) || severity == 0 {
		return "Unused inline config ('${id}' ${already})."
	}
	if !contains_different_property(json2.Any(options[1..]), json2.Any(existing[1..])) {
		return if items.len == 1 {
			"Unused inline config ('${id}' ${already})."
		} else {
			"Unused inline config ('${id}' ${already} with the same options)."
		}
	}
	return ''
}

// default_options_of are the meta.defaultOptions of a rule: the ones ESLint gave when it resolved
// the configuration, or the ones veslint has for the rules of ESLint and of typescript-eslint.
fn (cfg &LintConfig) default_options_of(id string) []json2.Any {
	if !cfg.strict_plugins {
		return eslint_default_options(id)
	}
	defaults := cfg.rule_defaults[id] or { return []json2.Any{} }
	return if defaults is []json2.Any { defaults.as_array() } else { []json2.Any{} }
}

// deep_merge_arrays ports deepMergeArrays of ESLint: the options over the default ones.
fn deep_merge_arrays(first []json2.Any, second []json2.Any) []json2.Any {
	mut out := []json2.Any{}
	for i, value in first {
		out << if i < second.len { deep_merge_objects(value, second[i]) } else { value }
	}
	for i in first.len .. second.len {
		out << second[i]
	}
	return out
}

fn deep_merge_objects(first json2.Any, second json2.Any) json2.Any {
	if first !is map[string]json2.Any || second !is map[string]json2.Any {
		return second
	}
	base := first.as_map()
	mut result := base.clone()
	for key, value in second.as_map() {
		result[key] = if key in base {
			deep_merge_objects(base[key] or { value }, value)
		} else {
			value
		}
	}
	return json2.Any(result)
}

// contains_different_property ports containsDifferentProperty of ESLint: whether a value of the
// options of a comment is not in the configured ones, or is another.
fn contains_different_property(input json2.Any, original json2.Any) bool {
	if input is []json2.Any {
		if original !is []json2.Any {
			return true
		}
		a := input.as_array()
		b := original.as_array()
		if a.len != b.len {
			return true
		}
		for i, value in a {
			if contains_different_property(value, b[i]) {
				return true
			}
		}
		return false
	}
	if input is map[string]json2.Any {
		if original !is map[string]json2.Any {
			return true
		}
		a := input.as_map()
		b := original.as_map()
		if a.len != b.len {
			return true
		}
		for key, value in a {
			other := b[key] or { return true }
			if contains_different_property(value, other) {
				return true
			}
		}
		return false
	}
	if original is []json2.Any || original is map[string]json2.Any {
		return true
	}
	// Two values that are not objects: the same one or not (a number is one whatever its form).
	a := input.json_str()
	b := original.json_str()
	if a != b && json_text_is_number(a) && json_text_is_number(b) {
		return a.f64() != b.f64()
	}
	return a != b
}

fn json_text_is_number(text string) bool {
	return text.len > 0 && (text[0] == `-` || (text[0] >= `0` && text[0] <= `9`))
}

// GlobalEntry is one name of a `/* global a, b: writable */` comment with its value, if any.
struct GlobalEntry {
	name      string
	value     string
	has_value bool
}

// global_entries ports Object.entries(parseStringConfig(value)) for a `/* global */` comment: its
// names, each with the text between its first and its second `:`. A repeated name keeps its
// place and takes the last value; as in any JavaScript object, the names that are array indexes
// come first, in ascending order, and `__proto__` is not a property.
fn global_entries(value string) []GlobalEntry {
	// The spaces around `:` and `,` do not count; then the names are split at spaces and commas.
	mut compact := []rune{}
	runes := js_trim(value).runes()
	mut i := 0
	for i < runes.len {
		mut j := i
		for j < runes.len && is_js_space(runes[j]) {
			j++
		}
		if j < runes.len && runes[j] in [`:`, `,`] {
			compact << runes[j]
			j++
			for j < runes.len && is_js_space(runes[j]) {
				j++
			}
			i = j
			continue
		}
		if j > i {
			compact << ` `
			i = j
			continue
		}
		compact << runes[i]
		i++
	}
	mut order := []string{}
	mut by_name := map[string]GlobalEntry{}
	for item in compact.string().replace(',', ' ').split(' ') {
		if item == '' {
			continue
		}
		parts := item.split(':')
		if parts[0] == '__proto__' {
			continue
		}
		if parts[0] !in by_name {
			order << parts[0]
		}
		by_name[parts[0]] = GlobalEntry{
			name:      parts[0]
			value:     if parts.len > 1 { parts[1] } else { '' }
			has_value: parts.len > 1
		}
	}
	mut indexes := order.filter(is_array_index_key(it))
	indexes.sort_with_compare(fn (a &string, b &string) int {
		return int(a.u64() > b.u64()) - int(a.u64() < b.u64())
	})
	mut out := []GlobalEntry{}
	for name in indexes {
		out << by_name[name]
	}
	for name in order {
		if !is_array_index_key(name) {
			out << by_name[name]
		}
	}
	return out
}

// exported_names ports ConfigCommentParser.parseListConfig on the value of an `/* exported */`
// comment: the names between commas, trimmed and without the quotes around them.
fn exported_names(value string) []string {
	mut out := []string{}
	for item in value.split(',') {
		mut name := js_trim(item)
		// /^(?<quote>['"]?)(?<ruleId>.*)\k<quote>$/su
		if name.len >= 2 && name[0] in [`'`, `"`] && name[name.len - 1] == name[0] {
			name = name[1..name.len - 1]
		}
		// `items.__proto__ = true` adds no key.
		if name != '' && name != '__proto__' && name !in out {
			out << name
		}
	}
	return out
}

// is_array_index_key: the property name is an integer index (the canonical text of a number up to
// 2^32 - 2), which JavaScript lists before the other properties of an object.
fn is_array_index_key(name string) bool {
	if name.len == 0 || name.len > 10 || (name.len > 1 && name[0] == `0`) {
		return false
	}
	for ch in name {
		if ch < `0` || ch > `9` {
			return false
		}
	}
	return name.u64() <= u64(4294967294)
}

// inline_severity is the severity of a rule value: 0, 1 or 2, or -1 if it is not one.
fn inline_severity(value json2.Any) int {
	return rule_severity_of(value)
}

// js_string_of_json is String(value) of a value read from a comment.
fn js_string_of_json(value json2.Any) string {
	if value is string {
		return value
	}
	if value is []json2.Any {
		return value.map(if it is json2.Null { '' } else { js_string_of_json(it) }).join(',')
	}
	if value is map[string]json2.Any {
		return '[object Object]'
	}
	return value.json_str()
}

// parse_inline_rules ports ConfigCommentParser.parseJSONLikeConfig: the rule ids, in order, and
// their values. What levn reads counts when every severity in it is valid; otherwise the text is
// turned into JSON (names quoted, one missing comma added) and parsed strictly, and the error says
// so when that fails too.
fn parse_inline_rules(text string) !([]string, []json2.Any) {
	if ids, values := levn_parse_object(text) {
		mut valid := true
		for value in values {
			first := if value is []json2.Any {
				if value.len > 0 { value[0] } else { json2.Any(json2.null) }
			} else {
				value
			}
			if inline_severity(first) < 0 {
				valid = false
				break
			}
		}
		if valid {
			return ids, values
		}
	}
	normalized := inline_json_text(text)
	json_text := '{${normalized}}'
	// The message is the one of V8's JSON.parse.
	message := v8_json_error(json_text)
	if message != '' {
		return error("Failed to parse JSON from '${normalized}': ${message}")
	}
	root := json2.decode[json2.Any](json_text) or {
		return error("Failed to parse JSON from '${normalized}': not valid JSON")
	}
	if root !is map[string]json2.Any {
		return error("Failed to parse JSON from '${normalized}': not an object")
	}
	object := root.as_map()
	mut ids := []string{}
	mut values := []json2.Any{}
	for id, value in object {
		ids << id
		values << value
	}
	return ids, values
}

// inline_json_text ports the fallback's normalization: every run of letters, digits, `-` and `/`
// before a `:` gets quotes, and the first `]` or digit followed by spaces and a `"` gets a comma.
fn inline_json_text(text string) string {
	runes := text.runes()
	mut out := []rune{}
	mut i := 0
	for i < runes.len {
		if !inline_name_rune(runes[i]) {
			out << runes[i]
			i++
			continue
		}
		mut j := i
		for j < runes.len && inline_name_rune(runes[j]) {
			j++
		}
		if j < runes.len && runes[j] == `:` {
			out << `"`
			out << runes[i..j]
			out << `"`
			out << `:`
			i = j + 1
		} else {
			out << runes[i..j]
			i = j
		}
	}
	for k := 0; k < out.len; k++ {
		if out[k] != `]` && !(out[k] >= `0` && out[k] <= `9`) {
			continue
		}
		mut j := k + 1
		for j < out.len && is_js_space(out[j]) {
			j++
		}
		if j > k + 1 && j < out.len && out[j] == `"` {
			mut joined := out[..k + 1].clone()
			joined << `,`
			joined << out[j..]
			return joined.string()
		}
	}
	return out.string()
}

fn inline_name_rune(r rune) bool {
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`) || r == `-`
		|| r == `/`
}

// collect_disable_directives ports getDisableDirectives and createDisableDirectives.
fn collect_disable_directives(mut result InlineConfig, config LintConfig) {
	for i, comment in result.comments {
		kind := match comment.label {
			'eslint-disable' { 'disable' }
			'eslint-enable' { 'enable' }
			'eslint-disable-line' { 'disable-line' }
			'eslint-disable-next-line' { 'disable-next-line' }
			else { continue }
		}
		if kind == 'disable-line' && comment.line != comment.end_line {
			result.problems << directive_problem(comment, 'error', problem_rule, 'eslint-disable-line comment should not span multiple lines.')
			continue
		}
		rule_ids := parse_list_config(comment.value)
		result.comments[i].rule_ids = rule_ids
		// A disable-next-line directive counts from the end of its comment.
		line := if kind == 'disable-next-line' { comment.end_line } else { comment.line }
		column := if kind == 'disable-next-line' { comment.end_column } else { comment.column }
		if rule_ids.len == 0 {
			result.directives << DisableDirective{
				kind:    kind
				line:    line
				column:  column
				comment: i
			}
			continue
		}
		for id in rule_ids {
			if !config.rule_exists(id) {
				result.problems << directive_problem(comment, 'error', id, "Definition for rule '${id}' was not found.")
				continue
			}
			result.directives << DisableDirective{
				kind:     kind
				line:     line
				column:   column
				rule:     id
				has_rule: true
				comment:  i
			}
		}
	}
}

// directive_entry_less orders entries by location, and by insertion among equals.
fn directive_entry_compare(a &DirectiveEntry, b &DirectiveEntry) int {
	if a.line != b.line {
		return a.line - b.line
	}
	if a.column != b.column {
		return a.column - b.column
	}
	return a.order - b.order
}

// UnusedDirective is a directive applyDirectives found unused, pending its report.
struct UnusedDirective {
	entry  DirectiveEntry
	enable bool // an unused `eslint-enable`
}

// apply_disable_directives ports applyDisableDirectives: the findings of the rules and the
// problems of the comments, without the ones a directive suppresses, plus the directives that
// suppress nothing, in order.
fn (mut c Checker) apply_disable_directives(findings []Finding, inline InlineConfig, config LintConfig) []Finding {
	mut all := findings.clone()
	all << inline.problems
	if all.len == 0 && inline.directives.len == 0 {
		return all
	}
	mut lines := []int{cap: all.len}
	mut columns := []int{cap: all.len}
	for f in all {
		lines << finding_line(inline.lines, f)
		columns << utf16_column(c.src, f.stmt.start_byte) + 1
	}
	mut order := []int{len: all.len, init: index}
	order.sort_with_compare(fn [lines, columns] (a &int, b &int) int {
		if lines[*a] != lines[*b] {
			return lines[*a] - lines[*b]
		}
		if columns[*a] != columns[*b] {
			return columns[*a] - columns[*b]
		}
		return *a - *b
	})
	if inline.directives.len == 0 {
		return order.map(all[it])
	}
	mut block := []DirectiveEntry{}
	mut line_entries := []DirectiveEntry{}
	for i, d in inline.directives {
		match d.kind {
			'disable', 'enable' {
				block << DirectiveEntry{
					disable:  d.kind == 'disable'
					line:     d.line
					column:   d.column
					rule:     d.rule
					has_rule: d.has_rule
					source:   i
					order:    block.len
				}
			}
			else {
				first := if d.kind == 'disable-line' { d.line } else { d.line + 1 }
				line_entries << DirectiveEntry{
					disable:  true
					line:     first
					column:   1
					rule:     d.rule
					has_rule: d.has_rule
					source:   i
					order:    line_entries.len
				}
				line_entries << DirectiveEntry{
					line:     first + 1
					column:   0
					rule:     d.rule
					has_rule: d.has_rule
					source:   i
					order:    line_entries.len
				}
			}
		}
	}
	block.sort_with_compare(directive_entry_compare)
	line_entries.sort_with_compare(directive_entry_compare)
	ids := order.map(all[it].eslint_id())
	sorted_lines := order.map(lines[it])
	sorted_columns := order.map(columns[it])
	mut suppressed := []bool{len: order.len}
	// The rules veslint does not have that are on in this file: the ones of the configuration that
	// no comment turns off, and the ones a comment turns on.
	mut other_active := config.other_active.filter(it !in inline.other_off)
	other_active << inline.other_active
	other := other_active.len > 0
	mut unused := []Finding{}
	for entries in [block, line_entries] {
		used := directive_pass(entries, ids, sorted_lines, sorted_columns, mut suppressed)
		if config.report_unused == 0 {
			continue
		}
		mut unused_disable := []DirectiveEntry{}
		mut unused_enable := []DirectiveEntry{}
		used_enable := used_enable_directives(entries)
		for i, entry in entries {
			if entry.disable {
				// Whether a rule veslint does not run would have used it cannot be known.
				unknown := if entry.has_rule { entry.rule in other_active } else { other }
				if !used[i] && !unknown {
					unused_disable << entry
				}
			} else if inline.directives[entry.source].kind == 'enable' && !used_enable[i] {
				unused_enable << entry
			}
		}
		unused << c.unused_directive_reports(unused_disable, inline, config)
		unused << c.unused_directive_reports(unused_enable, inline, config)
	}
	mut out := []Finding{}
	for i, index in order {
		if !suppressed[i] {
			out << all[index]
		}
	}
	if unused.len == 0 {
		return out
	}
	// Problems first, then the unused directives; sorted by location, stable.
	out << unused
	mut out_lines := out.map(finding_line(inline.lines, it))
	mut out_columns := []int{cap: out.len}
	for f in out {
		out_columns << utf16_column(c.src, f.stmt.start_byte) + 1
	}
	mut out_order := []int{len: out.len, init: index}
	out_order.sort_with_compare(fn [out_lines, out_columns] (a &int, b &int) int {
		if out_lines[*a] != out_lines[*b] {
			return out_lines[*a] - out_lines[*b]
		}
		if out_columns[*a] != out_columns[*b] {
			return out_columns[*a] - out_columns[*b]
		}
		return *a - *b
	})
	return out_order.map(out[it])
}

// directive_pass ports the loop of applyDirectives: a problem is suppressed when, of the
// directives before it that are for its rule or for every rule, the last ones are `disable`. It
// marks the problems suppressed and returns, per entry, whether it was the one that suppressed a
// problem nothing had suppressed yet.
fn directive_pass(entries []DirectiveEntry, ids []string, lines []int, columns []int, mut suppressed []bool) []bool {
	mut used := []bool{len: entries.len}
	for p in 0 .. ids.len {
		mut active := []int{}
		for i, entry in entries {
			if entry.line > lines[p] || (entry.line == lines[p] && entry.column > columns[p]) {
				break
			}
			if !entry.has_rule || entry.rule == ids[p] {
				if entry.disable {
					active << i
				} else {
					active.clear()
				}
			}
		}
		if active.len > 0 && !suppressed[p] {
			suppressed[p] = true
			used[active.last()] = true
		}
	}
	return used
}

// used_enable_directives ports collectUsedEnableDirectives: an `enable` is used when a `disable`
// before it is for its rule, or it is for every rule and some `disable` precedes it.
fn used_enable_directives(entries []DirectiveEntry) []bool {
	mut used := []bool{len: entries.len}
	mut enabled := map[string]int{} // rule -> entry; '' is the enable for every rule
	for index := entries.len - 1; index >= 0; index-- {
		entry := entries[index]
		if entry.disable {
			if enabled.len == 0 {
				continue
			}
			if !entry.has_rule {
				for _, i in enabled {
					used[i] = true
				}
				enabled.clear()
			} else if entry.rule in enabled {
				used[enabled[entry.rule]] = true
			} else if '' in enabled {
				used[enabled['']] = true
			}
		} else if !entry.has_rule {
			enabled.clear()
			enabled[''] = index
		} else {
			enabled[entry.rule] = index
		}
	}
	return used
}

// unused_directive_reports ports processUnusedDirectives and the messages of applyDirectives: the
// unused directives of a comment give one report when they are all of its rules, and one per rule
// otherwise; each with the fix that removes the comment or the rule.
fn (mut c Checker) unused_directive_reports(entries []DirectiveEntry, inline InlineConfig, config LintConfig) []Finding {
	mut groups := [][]DirectiveEntry{}
	mut group_of := map[int]int{} // comment -> group
	for entry in entries {
		comment := inline.directives[entry.source].comment
		if comment in group_of {
			groups[group_of[comment]] << entry
		} else {
			group_of[comment] = groups.len
			groups << [entry]
		}
	}
	mut out := []Finding{}
	for group in groups {
		comment := inline.comments[inline.directives[group[0].source].comment]
		enable := inline.directives[group[0].source].kind == 'enable'
		group_rules := group.filter(it.has_rule).map(it.rule)
		remaining := comment.rule_ids.filter(it !in group_rules)
		if remaining.len > 0 {
			for entry in group {
				has_fix, fix := c.directive_rule_removal(comment, entry.rule)
				out << unused_directive_finding(comment, enable, "'${entry.rule}'", config,
					has_fix, fix)
			}
			continue
		}
		quoted := group_rules.map("'${it}'")
		description := if quoted.len <= 2 {
			quoted.join(' or ')
		} else {
			quoted[..quoted.len - 1].join(', ') + ', or ' + quoted.last()
		}
		// The whole comment goes, and a space stays in its place.
		out << unused_directive_finding(comment, enable, description, config, true, Fix{
			start: comment.start
			end:   comment.end
			text:  ' '
		})
	}
	return out
}

fn unused_directive_finding(comment DirectiveComment, enable bool, description string, config LintConfig, has_fix bool, fix Fix) Finding {
	text := if enable {
		if description != '' {
			'Unused eslint-enable directive (no matching eslint-disable directives were found for ${description}).'
		} else {
			'Unused eslint-enable directive (no matching eslint-disable directives were found).'
		}
	} else if description != '' {
		'Unused eslint-disable directive (no problems were reported from ${description}).'
	} else {
		'Unused eslint-disable directive (no problems were reported).'
	}
	problem := directive_problem(comment, if config.report_unused == 1 { 'warning' } else { 'error' },
		problem_rule, text)
	return Finding{
		...problem
		// ESLint gives where the comment starts, and no end (applyDirectives reports a `loc` that
		// is a position).
		stmt:    Ident{
			...problem.stmt
			end_byte: -1
		}
		has_fix: has_fix
		fix:     fix
	}
}

// directive_rule_removal ports createIndividualDirectivesRemoval: the fix that takes one rule out
// of the list of a comment, with one of the commas around it.
fn (mut c Checker) directive_rule_removal(comment DirectiveComment, rule string) (bool, Fix) {
	list_text := comment.value
	list_start := c.src.index_after(list_text, comment.start) or { return false, Fix{} }
	// escape-string-regexp
	mut escaped := []u8{}
	for ch in rule.bytes() {
		if ch == `-` {
			escaped << '\\x2d'.bytes()
			continue
		}
		if ch in '|\\{}()[]^$+*?.'.bytes() {
			escaped << `\\`
		}
		escaped << ch
	}
	pattern := '(?:^|\\s*,\\s*)(?<quote>[\'"]?)${escaped.bytestr()}\\k<quote>(?:\\s*,\\s*|$)'
	prog := jsregexp.regexp_compile(pattern) or { return false, Fix{} }
	found, from, to := jsregexp.regexp_search(prog, list_text) or { return false, Fix{} }
	if !found {
		return false, Fix{}
	}
	runes := list_text.runes()
	match_start := list_start + runes[..from].string().len
	matched := runes[from..to].string()
	first_comma := matched.index(',') or { -1 }
	last_comma := matched.last_index(',') or { -1 }
	if first_comma != last_comma {
		return true, Fix{
			start: match_start + first_comma
			end:   match_start + last_comma
		}
	}
	return true, Fix{
		start: match_start
		end:   match_start + matched.len
	}
}
