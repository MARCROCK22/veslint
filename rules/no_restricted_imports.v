module rules

import json2
import jsregexp
import time
import treesitter { Ident, children, named_children, node_field, node_kind, position_of }

// Port of the `no-restricted-imports` rule of ESLint 10.6.0. The `group` patterns are gitignore
// rules (gitignore.v).

const nrim_messages = {
	'path':                                                    "'{{importSource}}' import is restricted from being used."
	'pathWithCustomMessage':                                   "'{{importSource}}' import is restricted from being used. {{customMessage}}"
	'patterns':                                                "'{{importSource}}' import is restricted from being used by a pattern."
	'patternWithCustomMessage':                                "'{{importSource}}' import is restricted from being used by a pattern. {{customMessage}}"
	'patternAndImportName':                                    "'{{importName}}' import from '{{importSource}}' is restricted from being used by a pattern."
	'patternAndImportNameWithCustomMessage':                   "'{{importName}}' import from '{{importSource}}' is restricted from being used by a pattern. {{customMessage}}"
	'patternAndEverything':                                    "* import is invalid because {{importNames}} from '{{importSource}}' {{isOrAre}} restricted from being used by a pattern."
	'patternAndEverythingWithRegexImportName':                 "* import is invalid because import name matching '{{importNames}}' pattern from '{{importSource}}' is restricted from being used."
	'patternAndEverythingWithCustomMessage':                   "* import is invalid because {{importNames}} from '{{importSource}}' {{isOrAre}} restricted from being used by a pattern. {{customMessage}}"
	'patternAndEverythingWithRegexImportNameAndCustomMessage': "* import is invalid because import name matching '{{importNames}}' pattern from '{{importSource}}' is restricted from being used. {{customMessage}}"
	'everything':                                              "* import is invalid because {{importNames}} from '{{importSource}}' {{isOrAre}} restricted."
	'everythingWithCustomMessage':                             "* import is invalid because {{importNames}} from '{{importSource}}' {{isOrAre}} restricted. {{customMessage}}"
	'importName':                                              "'{{importName}}' import from '{{importSource}}' is restricted."
	'importNameWithCustomMessage':                             "'{{importName}}' import from '{{importSource}}' is restricted. {{customMessage}}"
	'allowedImportName':                                       "'{{importName}}' import from '{{importSource}}' is restricted because only {{allowedImportNames}} {{isOrAre}} allowed."
	'allowedImportNameWithCustomMessage':                      "'{{importName}}' import from '{{importSource}}' is restricted because only {{allowedImportNames}} {{isOrAre}} allowed. {{customMessage}}"
	'everythingWithAllowImportNames':                          "* import is invalid because only {{allowedImportNames}} from '{{importSource}}' {{isOrAre}} allowed."
	'everythingWithAllowImportNamesAndCustomMessage':          "* import is invalid because only {{allowedImportNames}} from '{{importSource}}' {{isOrAre}} allowed. {{customMessage}}"
	'allowedImportNamePattern':                                "'{{importName}}' import from '{{importSource}}' is restricted because only imports that match the pattern '{{allowedImportNamePattern}}' are allowed from '{{importSource}}'."
	'allowedImportNamePatternWithCustomMessage':               "'{{importName}}' import from '{{importSource}}' is restricted because only imports that match the pattern '{{allowedImportNamePattern}}' are allowed from '{{importSource}}'. {{customMessage}}"
	'everythingWithAllowedImportNamePattern':                  "* import is invalid because only imports that match the pattern '{{allowedImportNamePattern}}' from '{{importSource}}' are allowed."
	'everythingWithAllowedImportNamePatternWithCustomMessage': "* import is invalid because only imports that match the pattern '{{allowedImportNamePattern}}' from '{{importSource}}' are allowed. {{customMessage}}"
}

// NrimPath is an entry of `paths` (a string gives one with nothing set).
struct NrimPath {
	message            string
	import_names       ?[]string
	allow_import_names ?[]string
	allow_type_imports bool
}

// NrimPattern is an entry of `patterns`: its gitignore group or regular expression, and the rest.
struct NrimPattern {
	regex                     ?jsregexp.RegexpProgram
	message                   string
	import_names              ?[]string
	import_name_pattern       ?jsregexp.RegexpProgram
	import_name_pattern_text  string // String(new RegExp(p, "u"))
	allow_import_names        ?[]string
	allow_import_name_pattern ?jsregexp.RegexpProgram
	allow_pattern_text        string
	allow_type_imports        bool
mut:
	matcher ?Gitignore
}

struct NrimOptions {
	paths    map[string][]NrimPath
	patterns []NrimPattern
}

fn nrim_strings(value ?json2.Any) ?[]string {
	v := value?
	if v !is []json2.Any {
		return none
	}
	return v.as_array().map(it.str())
}

fn nrim_flag(m map[string]json2.Any, key string) bool {
	value := m[key] or { return false }
	return value is bool && value as bool
}

fn nrim_text(m map[string]json2.Any, key string) string {
	value := m[key] or { return '' }
	return if value is string { value } else { '' }
}

// nrim_regexp_text is String(new RegExp(pattern, "u")): the escaped source between slashes.
fn nrim_regexp_text(pattern string) string {
	value := jsregexp.regexp_new(utf16_units(pattern), 'u') or { return '/${pattern}/u' }
	return '/${stv_units_string(value.source)}/u'
}

fn nrim_options(options []json2.Any) !NrimOptions {
	mut paths_list := options.clone()
	mut patterns_list := []json2.Any{}
	if options.len > 0 && options[0] is map[string]json2.Any {
		first := options[0].as_map()
		if 'paths' in first || 'patterns' in first {
			paths_list = if value := first['paths'] {
				if value is []json2.Any { value.clone() } else { []json2.Any{} }
			} else {
				[]json2.Any{}
			}
			if value := first['patterns'] {
				if value is []json2.Any {
					patterns_list = value.clone()
				}
			}
		}
	}
	mut paths := map[string][]NrimPath{}
	for item in paths_list {
		if item is string {
			paths[item] << NrimPath{}
			continue
		}
		if item !is map[string]json2.Any {
			return error('the paths of `${no_restricted_imports}` must be names or objects')
		}
		m := item.as_map()
		paths[nrim_text(m, 'name')] << NrimPath{
			message:            nrim_text(m, 'message')
			import_names:       nrim_strings(m['importNames'] or { json2.Null{} })
			allow_import_names: nrim_strings(m['allowImportNames'] or { json2.Null{} })
			allow_type_imports: nrim_flag(m, 'allowTypeImports')
		}
	}
	mut patterns := []NrimPattern{}
	if patterns_list.len > 0 && patterns_list[0] is string {
		patterns_list = [json2.Any({
			'group': json2.Any(patterns_list)
		})]
	}
	for item in patterns_list {
		if item !is map[string]json2.Any {
			return error('the patterns of `${no_restricted_imports}` must be names or objects')
		}
		m := item.as_map()
		case_sensitive := nrim_flag(m, 'caseSensitive')
		mut matcher := ?Gitignore(none)
		if group := nrim_strings(m['group'] or { json2.Null{} }) {
			matcher = new_gitignore(group, !case_sensitive)
		}
		mut regex := ?jsregexp.RegexpProgram(none)
		if value := m['regex'] {
			if value is string {
				source := if case_sensitive { value } else { '(?i:${value})' }
				regex = jsregexp.regexp_compile(source) or {
					return error('the regex of `${no_restricted_imports}` is not a valid regular expression')
				}
			}
		}
		name_pattern := nrim_text(m, 'importNamePattern')
		allow_pattern := nrim_text(m, 'allowImportNamePattern')
		patterns << NrimPattern{
			matcher:                   matcher
			regex:                     regex
			message:                   nrim_text(m, 'message')
			import_names:              nrim_strings(m['importNames'] or { json2.Null{} })
			import_name_pattern:       if name_pattern != '' {
				?jsregexp.RegexpProgram(jsregexp.regexp_compile(name_pattern)!)
			} else {
				?jsregexp.RegexpProgram(none)
			}
			import_name_pattern_text:  if name_pattern != '' {
				nrim_regexp_text(name_pattern)
			} else {
				''
			}
			allow_import_names:        nrim_strings(m['allowImportNames'] or { json2.Null{} })
			allow_import_name_pattern: if allow_pattern != '' {
				?jsregexp.RegexpProgram(jsregexp.regexp_compile(allow_pattern)!)
			} else {
				?jsregexp.RegexpProgram(none)
			}
			allow_pattern_text:        if allow_pattern != '' {
				nrim_regexp_text(allow_pattern)
			} else {
				''
			}
			allow_type_imports:        nrim_flag(m, 'allowTypeImports')
		}
	}
	return NrimOptions{
		paths:    paths
		patterns: patterns
	}
}

// NrimSpecifier is a specifier of an import or export: where it is reported, and whether it is
// type-only by itself.
struct NrimSpecifier {
	position  Ident
	type_only bool
}

// NrimNames are the names a declaration imports, in the order of their first specifier.
struct NrimNames {
mut:
	order []string
	names map[string][]NrimSpecifier
}

fn (mut n NrimNames) add(name string, specifier NrimSpecifier) {
	if name !in n.names {
		n.order << name
	}
	n.names[name] << specifier
}

// nrim_list ports formatImportNames: Intl.ListFormat("en-US") of the quoted names.
fn nrim_list(names []string) string {
	quoted := names.map("'${it}'")
	return match quoted.len {
		0 { '' }
		1 { quoted[0] }
		2 { '${quoted[0]} and ${quoted[1]}' }
		else { quoted[..quoted.len - 1].join(', ') + ', and ' + quoted.last() }
	}
}

fn nrim_is_or_are(names []string) string {
	return if names.len == 1 { 'is' } else { 'are' }
}

fn (mut c Checker) lint_no_restricted_imports(root C.TSNode, abs_path string, mut stats Stats) ![]Finding {
	sw := time.new_stopwatch()
	mut o := nrim_options(c.rule_options(no_restricted_imports))!
	mut findings := []Finding{}
	if o.paths.len == 0 && o.patterns.len == 0 {
		return findings
	}
	for node in c.nodes_of_kinds(root, ['import_statement', 'export_statement'], []) {
		stats.checked++
		parts := children(node)
		mut source_node := node_field(node, 'source') or { node }
		mut imported := NrimNames{}
		mut type_only := false
		mut equals := false
		if node_kind(node) == 'import_statement' {
			if clause := parts.filter(node_kind(it) == 'import_require_clause')[0] {
				// TSImportEqualsDeclaration with an external module reference.
				equals = true
				source_node = named_children(clause).filter(node_kind(it) == 'string')[0] or {
					continue
				}
				type_only = parts.any(node_kind(it) == 'type')
			} else {
				if node_kind(source_node) != 'string' {
					continue
				}
				statement_type := parts.any(node_kind(it) == 'type')
				mut specifier_types := []bool{}
				if clause := parts.filter(node_kind(it) == 'import_clause')[0] {
					for child in named_children(clause) {
						match node_kind(child) {
							'identifier' {
								imported.add('default', NrimSpecifier{position_of(child), false})
								specifier_types << false
							}
							'namespace_import' {
								imported.add('*', NrimSpecifier{position_of(child), false})
								specifier_types << false
							}
							'named_imports' {
								for specifier in named_children(child) {
									if node_kind(specifier) != 'import_specifier' {
										continue
									}
									imported_name := node_field(specifier, 'name') or { continue }
									is_type := children(specifier).any(node_kind(it) == 'type')
									imported.add(c.nre_name(imported_name), NrimSpecifier{position_of(specifier), is_type})
									specifier_types << is_type
								}
							}
							else {}
						}
					}
				}
				type_only = statement_type
					|| (specifier_types.len > 0 && specifier_types.all(it))
			}
		} else {
			if node_kind(source_node) != 'string' {
				continue
			}
			statement_type := parts.any(node_kind(it) == 'type')
			if star := parts.filter(node_kind(it) in ['*', 'namespace_export'])[0] {
				// ExportAllDeclaration: its star token.
				position := if node_kind(star) == 'namespace_export' {
					position_of(children(star)[0] or { star })
				} else {
					position_of(star)
				}
				imported.add('*', NrimSpecifier{position, false})
				type_only = statement_type
			} else if clause := parts.filter(node_kind(it) == 'export_clause')[0] {
				mut specifier_types := []bool{}
				for specifier in named_children(clause) {
					if node_kind(specifier) != 'export_specifier' {
						continue
					}
					local := node_field(specifier, 'name') or { continue }
					is_type := children(specifier).any(node_kind(it) == 'type')
					imported.add(c.nre_name(local), NrimSpecifier{position_of(specifier), is_type})
					specifier_types << is_type
				}
				type_only = statement_type || (specifier_types.len > 0 && specifier_types.all(it))
			} else {
				continue
			}
		}
		raw_source := c.literal_string_value(source_node) or { continue }
		import_source := if equals { raw_source } else { js_trim(raw_source) }
		c.nrim_check_paths(node, import_source, imported, type_only, o, mut findings)
		for mut group in o.patterns {
			if !nrim_is_restricted(import_source, mut group) {
				continue
			}
			c.nrim_report_pattern(node, group, imported, import_source, type_only, mut findings)
		}
	}
	stats.eval_ms += ms(sw.elapsed())
	return findings
}

fn nrim_is_restricted(source string, mut group NrimPattern) bool {
	if regex := group.regex {
		return jsregexp.regexp_test(regex, source) or { false }
	}
	if mut matcher := group.matcher {
		result := matcher.ignores(source)
		group.matcher = matcher
		return result
	}
	return false
}

// nrim_finding is a report with the message `plain`, or `custom_id` with the custom message.
fn nrim_finding(position Ident, plain string, custom_id string, custom string, data map[string]string) Finding {
	mut all := data.clone()
	all['customMessage'] = custom
	return Finding{
		stmt:       position
		message_id: if custom != '' { custom_id } else { plain }
		data:       all
	}
}

// nrim_check_paths ports checkRestrictedPathAndReport.
fn (c &Checker) nrim_check_paths(node C.TSNode, source string, names NrimNames, type_only bool, o NrimOptions, mut findings []Finding) {
	entries := o.paths[source] or { return }
	for entry in entries {
		custom := entry.message
		if entry.allow_type_imports && type_only {
			continue
		}
		if entry.import_names == none && entry.allow_import_names == none {
			findings << nrim_finding(position_of(node), 'path', 'pathWithCustomMessage', custom, {
				'importSource': source
			})
			continue
		}
		for name in names.order {
			specifiers := names.names[name]
			if name == '*' {
				if restricted := entry.import_names {
					findings << nrim_finding(specifiers[0].position, 'everything', 'everythingWithCustomMessage',
						custom, {
							'importSource': source
							'importNames':  nrim_list(restricted)
							'isOrAre':      nrim_is_or_are(restricted)
						})
				} else if allowed := entry.allow_import_names {
					findings << nrim_finding(specifiers[0].position, 'everythingWithAllowImportNames',
						'everythingWithAllowImportNamesAndCustomMessage', custom, {
							'importSource':       source
							'allowedImportNames': nrim_list(allowed)
							'isOrAre':            nrim_is_or_are(allowed)
						})
				}
				continue
			}
			if restricted := entry.import_names {
				if name in restricted {
					for specifier in specifiers {
						if entry.allow_type_imports && specifier.type_only {
							continue
						}
						findings << nrim_finding(specifier.position, 'importName', 'importNameWithCustomMessage',
							custom, {
								'importSource': source
								'importName':   name
							})
					}
				}
			}
			if allowed := entry.allow_import_names {
				if name !in allowed {
					for specifier in specifiers {
						if entry.allow_type_imports && specifier.type_only {
							continue
						}
						findings << nrim_finding(specifier.position, 'allowedImportName', 'allowedImportNameWithCustomMessage',
							custom, {
								'importSource':       source
								'importName':         name
								'allowedImportNames': nrim_list(allowed)
								'isOrAre':            nrim_is_or_are(allowed)
							})
					}
				}
			}
		}
	}
}

// nrim_report_pattern ports reportPathForPatterns.
fn (c &Checker) nrim_report_pattern(node C.TSNode, group NrimPattern, names NrimNames, source string, type_only bool, mut findings []Finding) {
	if group.allow_type_imports && type_only {
		return
	}
	custom := group.message
	if group.import_names == none && group.allow_import_names == none
		&& group.import_name_pattern == none && group.allow_import_name_pattern == none {
		findings << nrim_finding(position_of(node), 'patterns', 'patternWithCustomMessage', custom, {
			'importSource': source
		})
		return
	}
	for name in names.order {
		specifiers := names.names[name]
		if name == '*' {
			position := specifiers[0].position
			if restricted := group.import_names {
				findings << nrim_finding(position, 'patternAndEverything', 'patternAndEverythingWithCustomMessage',
					custom, {
						'importSource': source
						'importNames':  nrim_list(restricted)
						'isOrAre':      nrim_is_or_are(restricted)
					})
			} else if allowed := group.allow_import_names {
				findings << nrim_finding(position, 'everythingWithAllowImportNames', 'everythingWithAllowImportNamesAndCustomMessage',
					custom, {
						'importSource':       source
						'allowedImportNames': nrim_list(allowed)
						'isOrAre':            nrim_is_or_are(allowed)
					})
			} else if group.allow_import_name_pattern != none {
				findings << nrim_finding(position, 'everythingWithAllowedImportNamePattern', 'everythingWithAllowedImportNamePatternWithCustomMessage',
					custom, {
						'importSource':             source
						'allowedImportNamePattern': group.allow_pattern_text
					})
			} else {
				findings << nrim_finding(position, 'patternAndEverythingWithRegexImportName', 'patternAndEverythingWithRegexImportNameAndCustomMessage',
					custom, {
						'importSource': source
						'importNames':  group.import_name_pattern_text
					})
			}
			continue
		}
		mut restricted_name := false
		if restricted := group.import_names {
			restricted_name = name in restricted
		}
		if !restricted_name {
			if pattern := group.import_name_pattern {
				restricted_name = jsregexp.regexp_test(pattern, name) or { false }
			}
		}
		if restricted_name {
			for specifier in specifiers {
				if group.allow_type_imports && specifier.type_only {
					continue
				}
				findings << nrim_finding(specifier.position, 'patternAndImportName', 'patternAndImportNameWithCustomMessage',
					custom, {
						'importSource': source
						'importName':   name
					})
			}
		}
		if allowed := group.allow_import_names {
			if name !in allowed {
				for specifier in specifiers {
					if group.allow_type_imports && specifier.type_only {
						continue
					}
					findings << nrim_finding(specifier.position, 'allowedImportName', 'allowedImportNameWithCustomMessage',
						custom, {
							'importSource':       source
							'importName':         name
							'allowedImportNames': nrim_list(allowed)
							'isOrAre':            nrim_is_or_are(allowed)
						})
				}
			}
		} else if pattern := group.allow_import_name_pattern {
			if !(jsregexp.regexp_test(pattern, name) or { false }) {
				for specifier in specifiers {
					if group.allow_type_imports && specifier.type_only {
						continue
					}
					findings << nrim_finding(specifier.position, 'allowedImportNamePattern', 'allowedImportNamePatternWithCustomMessage',
						custom, {
							'importSource':             source
							'importName':               name
							'allowedImportNamePattern': group.allow_pattern_text
						})
				}
			}
		}
	}
}
