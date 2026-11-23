module main

import hash.fnv1a
import json2
import os
import rules
import strings
import tsgo

// The project a file takes its types from. typescript-eslint gets them from the project service
// (`parserOptions.projectService`) or from the programs of `parserOptions.project`, and when the
// file is in none of the projects it may take them from, its parser throws: ESLint reports that
// file as a fatal `Parsing error` at 0:0 and lints the others. veslint finds the project the
// same way (find_file_projects), after the snapshot, and reports the same error for such a file
// instead of linting it.

// TypeSource is where typescript-eslint gets the types of the files of a configuration
// (createParseSettings of typescript-estree 8.72.2).
enum TypeSource {
	// veslint's own JSON configurations (with neither `projectService` nor `project`) and --rule:
	// veslint gets the types as the project service does, so a file in no project is the project
	// service's parsing error when a rule needs its types, and is linted without a program (as
	// ESLint lints it without them) when none does.
	implicit
	// The project service.
	service
	// The programs of `parserOptions.project` (or of `programs`).
	project
	// Neither: typescript-eslint builds no program, so no file stops it.
	none
}

// FileProjects is what find_file_projects found besides the files it changed.
struct FileProjects {
mut:
	// The tsconfig files that some file now takes its types from and the lint's snapshot does not
	// have open yet.
	opened []string
}

// ProjectSearch answers whether the program of a tsconfig has a file. A file among the root files
// of its project (all the files of most projects) needs no request; for the others the programs
// are asked for in a snapshot of the search's own (`probe`), which the lint's snapshot never sees,
// so a lint whose files are all root files is not changed.
struct ProjectSearch {
mut:
	client &tsgo.Client = unsafe { nil }
	// The lint's snapshot, whose projects have their root files already.
	snap tsgo.UpdateSnapshotResponse
	// The root files of each tsconfig (those of `snap`, or parseConfigFile), by path_key.
	roots map[string]map[string]bool
	// The files of the program of each tsconfig, by path_key.
	programs map[string]map[string]bool
	probe    tsgo.UpdateSnapshotResponse = tsgo.UpdateSnapshotResponse{
		snapshot: no_snapshot
	}
}

fn (mut s ProjectSearch) roots_have(tsconfig string, key string) !bool {
	if tsconfig !in s.roots {
		mut names := []string{}
		mut known := false
		for p in s.snap.projects {
			if is_project_of(p, tsconfig) {
				names = p.parsed_command_line.file_names
				known = true
				break
			}
		}
		if !known {
			names = s.client.parse_config_file(tsconfig)!.file_names
		}
		mut keys := map[string]bool{}
		for name in names {
			keys[tsgo.path_key(name)] = true
		}
		s.roots[tsconfig] = keys.move()
	}
	return key in s.roots[tsconfig]
}

// program_has tells whether the program of a tsconfig has the file (by path_key): one of its root
// files, or a file they import (typescript-estree's getAstFromProgram, and the project service's
// containsScriptInfo).
fn (mut s ProjectSearch) program_has(tsconfig string, key string) !bool {
	if s.roots_have(tsconfig, key)! {
		return true
	}
	if tsconfig !in s.programs {
		if s.probe.snapshot == no_snapshot {
			s.probe = s.client.create_snapshot([tsconfig])!
		} else if !s.probe.projects.any(is_project_of(it, tsconfig)) {
			previous := s.probe.snapshot
			s.probe = s.client.update_snapshot_files(s.probe, [tsconfig], tsgo.FileChangeSet{})!
			if s.probe.snapshot != previous {
				s.client.release_snapshot(previous)!
			}
		}
		mut project := ''
		for p in s.probe.projects {
			if is_project_of(p, tsconfig) {
				project = p.id
				break
			}
		}
		if project == '' {
			return error('tsconfig ${tsconfig} is not in the tsgo snapshot (projects: ${s.probe.projects.map(it.id)})')
		}
		mut keys := map[string]bool{}
		for name in s.client.source_file_names(s.probe.snapshot, project)! {
			keys[tsgo.path_key(name)] = true
		}
		s.programs[tsconfig] = keys.move()
	}
	return key in s.programs[tsconfig]
}

fn (mut s ProjectSearch) close() {
	if s.probe.snapshot != no_snapshot {
		s.client.release_snapshot(s.probe.snapshot) or {}
		s.probe = tsgo.UpdateSnapshotResponse{
			snapshot: no_snapshot
		}
	}
}

// service_project ports how the project service finds the project of a file it opens
// (tryFindDefaultConfiguredProjectForOpenScriptInfo of TypeScript 6.0.3's server, which
// typescript-eslint 8.72.2 uses): the tsconfig veslint picked (the closest one) when its program
// has the file; else one of the projects it references (recursively) whose root files have it;
// else the same search from the next tsconfig.json up (forEachConfigFileLocation, which stops at
// `root`, the tsconfigRootDir, when the file is under it, and at a node_modules directory). ''
// when none has it.
fn (mut s ProjectSearch) service_project(tsconfig string, abs_path string, root string) !string {
	key := tsgo.path_key(abs_path)
	mut seen := map[string]bool{}
	mut current := tsconfig
	// Whether the search may leave the tsconfigRootDir: only for a file outside it.
	anywhere := !path_contains(root, os.dir(abs_path))
	for current != '' {
		seen[tsgo.path_key(current)] = true
		if s.program_has(current, key)! {
			return current
		}
		if found := s.referenced_project(current, key, mut seen) {
			return found
		}
		current = ancestor_tsconfig(current, root, anywhere)
		for current != '' && tsgo.path_key(current) in seen {
			current = ancestor_tsconfig(current, root, anywhere)
		}
	}
	return ''
}

// referenced_project is the first project the tsconfig references, depth first, whose root files
// have the file (isMatchedByConfig, before the project is loaded): tsserver's
// forEachResolvedProjectReferenceProjectLoad. The references are those of the raw file, which
// `extends` does not pass on.
fn (mut s ProjectSearch) referenced_project(tsconfig string, key string, mut seen map[string]bool) ?string {
	for reference in tsconfig_references(tsconfig) {
		reference_key := tsgo.path_key(reference)
		if reference_key in seen || !os.is_file(reference) {
			continue
		}
		seen[reference_key] = true
		if s.roots_have(reference, key) or { false } {
			return reference
		}
		if found := s.referenced_project(reference, key, mut seen) {
			return found
		}
	}
	return none
}

// tsconfig_references are the tsconfig files the `references` of a tsconfig name, as TypeScript
// resolves them (resolveProjectReferencePath: a path that is not a .json file is a directory with
// a tsconfig.json), relative to its directory.
fn tsconfig_references(tsconfig string) []string {
	text := os.read_file(tsconfig) or { return [] }
	raw := json2.decode[json2.Any](strip_jsonc(text)) or { return [] }
	if raw !is map[string]json2.Any {
		return []
	}
	references := raw.as_map()['references'] or { return [] }
	if references !is []json2.Any {
		return []
	}
	mut out := []string{}
	for item in references.as_array() {
		if item !is map[string]json2.Any {
			continue
		}
		path := item.as_map()['path'] or { continue }
		if path !is string {
			continue
		}
		mut target := path.str()
		if !os.is_abs_path(target) {
			target = os.join_path(os.dir(tsconfig), target)
		}
		if !target.to_lower().ends_with('.json') {
			target = os.join_path(target, 'tsconfig.json')
		}
		out << os.norm_path(target)
	}
	return out
}

// ancestor_tsconfig is the next tsconfig.json above the directory of `tsconfig` (the
// jsconfig.json of its directory, which tsserver looks at first, is not one veslint reads), within
// `root` unless `anywhere`, and not past a node_modules directory; '' when there is none.
fn ancestor_tsconfig(tsconfig string, root string, anywhere bool) string {
	mut directory := os.dir(tsconfig)
	for {
		if os.file_name(directory) == 'node_modules' {
			return ''
		}
		parent := os.dir(directory)
		if parent == directory || parent == '' {
			return ''
		}
		directory = parent
		if !anywhere && !path_contains(root, directory) {
			return ''
		}
		candidate := os.join_path(directory, 'tsconfig.json')
		if os.is_file(candidate) {
			return candidate
		}
	}
	return ''
}

// path_contains: `path` is `directory` or a path under it (containsPath, without case where file
// names have none).
fn path_contains(directory string, path string) bool {
	d := tsgo.path_key(directory).trim_right('/\\')
	p := tsgo.path_key(path)
	return p == d || p.starts_with(d + '/') || p.starts_with(d + os.path_separator)
}

// find_file_projects decides the project of each file that typescript-eslint would lint with
// types (its configuration has the project service or `parserOptions.project`), once the snapshot
// `snap` has the projects of the tsconfigs veslint picked for the files: a file in the program of
// the project typescript-eslint takes keeps it or moves to it (an ancestor or a referenced
// tsconfig, or the default project of allowDefaultProject: default_project_tsconfig), which
// `opened` lists when the snapshot does not have it, and a file in no such program gets ESLint's
// parsing error (RuleFile.fatal) instead. `typed` tells, for each configuration (by index),
// whether a rule of it needs types; `single_run` is whether ESLint would make a single run
// (is_single_run). With --project (`forced`), a file keeps the tsconfig given.
fn find_file_projects(mut client tsgo.Client, mut files []RuleFile, snap tsgo.UpdateSnapshotResponse, loaded &LoadedConfig, typed []bool, single_run bool, forced bool) !FileProjects {
	mut result := FileProjects{}
	patterns := loaded.service_patterns(files.filter(it.note == '').map(it.abs_path))
	mut search := ProjectSearch{
		client: client
		snap:   snap
	}
	defer {
		search.close()
	}
	// The files the default project has (defaultProjectMatchedFiles of typescript-estree), in the
	// order they are linted.
	mut defaulted := []string{}
	for i, f in files {
		if f.note != '' || f.fatal != '' || f.vue || f.svelte || f.tsconfig == '' {
			continue
		}
		config_index := loaded.file_config[f.abs_path] or { 0 }
		entry := loaded.config_entry(f.abs_path)
		mut fatal := ''
		mut tsconfig := f.tsconfig
		key := tsgo.path_key(f.ts_path)
		match entry.types {
			.none {
				continue
			}
			.project {
				if f.named.len > 0 {
					// The first of the projects whose program has the file (assign_named_projects
					// gave the first whose root files have it, or the closest tsconfig).
					mut found := ''
					for named in f.named {
						if search.program_has(named, key)! {
							found = named
							break
						}
					}
					if found == '' {
						fatal = project_not_found_message(f.abs_path, entry, f.named,
							single_run)
					} else {
						tsconfig = found
					}
				} else if !search.program_has(tsconfig, key)! {
					fatal = project_not_found_message(f.abs_path, entry, [tsconfig], single_run)
				}
			}
			.service, .implicit {
				candidate := !forced && f.abs_path in loaded.default_project
				found := if forced {
					if search.program_has(tsconfig, key)! { tsconfig } else { '' }
				} else if candidate && tsconfig == default_project_tsconfig(f.abs_path, entry).path {
					// No tsconfig.json at or above the file (without_tsconfig).
					''
				} else {
					search.service_project(tsconfig, f.abs_path, entry.root_dir())!
				}
				if candidate {
					if found != '' {
						fatal = '${f.abs_path} was included by allowDefaultProject but also was found in the project service. Consider removing it from allowDefaultProject.'
					} else {
						defaulted << f.abs_path
						if defaulted.len > entry.default_project_limit {
							fatal = too_many_default_files_message(defaulted, entry.default_project_limit)
						} else {
							tsconfig = default_project_tsconfig(f.abs_path, entry).path
						}
					}
				} else if found != '' {
					tsconfig = found
				} else if entry.types == .service || (config_index < typed.len && typed[config_index]) {
					fatal = service_not_found_message(f.abs_path, entry, patterns)
				}
			}
		}
		if fatal != '' {
			files[i] = RuleFile{
				...f
				fatal: fatal
			}
			continue
		}
		if tsconfig != f.tsconfig {
			if !snap.projects.any(is_project_of(it, tsconfig)) && tsconfig !in result.opened {
				result.opened << tsconfig
			}
			files[i] = RuleFile{
				...f
				tsconfig: tsconfig
			}
		}
	}
	return result
}

// default_project_tsconfig is the tsconfig veslint lints a file of the default project of
// allowDefaultProject with, and its text: the project service puts such a file alone in an
// inferred project (assignOrphanScriptInfoToInferredProject of TypeScript 6.0.3's server, with
// neither useSingleInferredProject nor useInferredProjectPerProjectRoot), with the compiler options
// of the `defaultProject` tsconfig (tsconfig.json by default, from the tsconfigRootDir), when it
// can be read (createProjectService of @typescript-eslint/project-service). It is a virtual file
// next to that tsconfig (or in the tsconfigRootDir), which extends it with only the file.
fn default_project_tsconfig(abs_path string, entry ConfigEntry) VirtualFile {
	root := entry.root_dir()
	given := if entry.default_project == '' { 'tsconfig.json' } else { entry.default_project }
	options := if os.is_abs_path(given) { given } else { os.abs_path(os.join_path(root, given)) }
	directory := if os.is_file(options) { os.dir(options) } else { root }
	path := os.join_path(directory, 'tsconfig.veslint-default-${fnv1a.sum64_string(abs_path).hex()}.json')
	extends := if os.is_file(options) { '"extends":${json_stringify(options)},' } else { '' }
	return VirtualFile{
		path: path
		text: '{${extends}"files":[${json_stringify(abs_path)}],"include":[]}'
	}
}

// VirtualFile is a file veslint gives tsgo that is not on disk.
struct VirtualFile {
	path string
	text string
}

// without_tsconfig is what a file with no tsconfig.json at or above it is linted with: the tsconfig
// of the default project when allowDefaultProject matches it, or typescript-eslint's parsing error
// (`fatal`) for a configuration it gets the types with (veslint's own, only when a rule of it needs
// types); none when typescript-eslint would lint it without a program, which veslint cannot.
fn without_tsconfig(abs_path string, loaded &LoadedConfig, lint_configs []rules.LintConfig, files []string) ?(string, string) {
	entry := loaded.config_entry(abs_path)
	if entry.types in [.service, .implicit] && abs_path in loaded.default_project {
		return default_project_tsconfig(abs_path, entry).path, ''
	}
	if entry.types == .implicit {
		index := loaded.file_config[abs_path] or { 0 }
		if index >= lint_configs.len || !configs_need_types([lint_configs[index]]) {
			return none
		}
	}
	fatal := missing_tsconfig_fatal(abs_path, entry, loaded.service_patterns(files))
	if fatal == '' {
		return none
	}
	return '', fatal
}

// default_project_tsconfigs are the virtual tsconfigs of the files allowDefaultProject matches
// (default_project_tsconfig), which tsgo must have from the start: a client with virtual files.
fn default_project_tsconfigs(loaded &LoadedConfig, abs_paths []string) map[string]string {
	mut out := map[string]string{}
	for abs_path in abs_paths {
		if abs_path in loaded.default_project {
			file := default_project_tsconfig(abs_path, loaded.config_entry(abs_path))
			out[file.path] = file.text
		}
	}
	return out
}

// too_many_default_files_message is typescript-estree's error for a file the default project would
// have past its limit (openClientFileFromProjectService), with the files it has (the first 20).
fn too_many_default_files_message(files []string, limit int) string {
	shown := files#[..20]
	more := if files.len > shown.len { '...and ${files.len - shown.len} more files\n' } else { '' }
	return 'Too many files (>${limit}) have matched the default project.\n\nHaving many files run with the default project is known to cause performance issues and slow down linting.\n\nSee https://tseslint.com/allowdefaultproject-glob-too-wide\n\nMatching files:\n' +
		shown.map('- ${it}').join('\n') + '\n${more}\nIf you absolutely need more files included, set parserOptions.projectService.maximumDefaultProjectFileMatchCount_THIS_WILL_SLOW_DOWN_LINTING to a larger value.'
}

// missing_tsconfig_fatal is the parsing error of a file without a tsconfig.json at or above it,
// with a configuration typescript-eslint gets the types with; '' with one without types, which
// typescript-eslint lints without a program.
fn missing_tsconfig_fatal(abs_path string, entry ConfigEntry, patterns []string) string {
	return match entry.types {
		.service {
			service_not_found_message(abs_path, entry, patterns)
		}
		.implicit {
			// When a rule needs types (without_tsconfig).
			service_not_found_message(abs_path, entry, patterns)
		}
		.project {
			if entry.projects.len > 0 {
				project_not_found_message(abs_path, entry, entry.projects, true)
			} else {
				// getProjectConfigFiles, for `project: true`.
				"project was set to `true` but couldn't find any tsconfig.json relative to '${abs_path}' within '${entry.root_dir()}'."
			}
		}
		.none {
			''
		}
	}
}

// service_not_found_message is typescript-estree's error for a file the project service has in no
// project (openClientFileFromProjectService), with the allowDefaultProject patterns of the project
// service (`patterns`, LoadedConfig.service_patterns) when it has some, which do not match it.
fn service_not_found_message(abs_path string, entry ConfigEntry, patterns []string) string {
	base := '${abs_path} was not found by the project service. Consider either including it in the tsconfig.json or including it in allowDefaultProject.'
	if patterns.len == 0 {
		return base
	}
	listed := '[' + patterns.map(json_stringify(it)).join(',') + ']'
	relative := node_relative(entry.root_dir(), abs_path)
	return "${base}\nallowDefaultProject is set to ${listed}, which does not match '${relative}'."
}

// project_not_found_message is typescript-estree's error for a file in none of the programs of
// `parserOptions.project` (`projects`): in a single run, the programs made once from the tsconfig
// files (useProvidedPrograms); otherwise, its watch programs (createProjectProgramError).
fn project_not_found_message(abs_path string, entry ConfigEntry, projects []string, single_run bool) string {
	root := entry.root_dir()
	if single_run {
		return '"parserOptions.project" has been provided for @typescript-eslint/parser.\nThe file was not found in any of the provided project(s): ${node_relative(root, abs_path)}'
	}
	described := describe_file_path(abs_path, root)
	programs := if projects.len == 1 {
		' ' + describe_file_path(projects[0], root)
	} else {
		'\n' + projects.map('- ' + describe_file_path(it, root)).join('\n')
	}
	mut lines := [
		'ESLint was configured to lint `${described}` with type information from `parserOptions.project`:${programs}',
	]
	if projects.len == 1 && tsconfig_references(projects[0]).len > 0 {
		lines << 'That TSConfig uses project "references" and doesn\'t include `${described}` directly, which is not supported by `parserOptions.project`.'
		lines << 'Either:'
		lines << '- Switch to `parserOptions.projectService`'
		lines << '- Use an ESLint-specific TSConfig'
		lines << 'See the typescript-eslint docs for more info: https://tseslint.com/are-project-references-supported'
		return lines.join('\n')
	}
	inclusions, specifiers := if projects.len == 1 {
		'that TSConfig does not', 'that TSConfig'
	} else {
		'none of those TSConfigs', 'one of those TSConfigs'
	}
	lines << 'However, ${inclusions} include this file, so type information is not available for it. Either:'
	lines << "- Change ESLint's list of included files to not include this file"
	lines << '- Change ${specifiers} to include this file'
	lines << '- Create a new TSConfig that includes this file and include it in your parserOptions.project'
	lines << 'See the typescript-eslint docs for more info: https://tseslint.com/none-of-those-tsconfigs-include-this-file'
	return lines.join('\n')
}

// describe_file_path ports typescript-estree's describeFilePath: a path under the tsconfigRootDir
// as `<tsconfigRootDir>/` and its relative path, and the others as they are.
fn describe_file_path(path string, root string) string {
	relative := node_relative(root, path)
	if relative != '' && !relative.starts_with('..') && !os.is_abs_path(relative) {
		return '<tsconfigRootDir>/${relative}'
	}
	// /^[(\w+:)\\/~]/: a character class, so any of those characters first.
	if path.len > 0 && (path[0].is_letter() || path[0].is_digit() || path[0] in [`_`, `(`, `+`,
		`:`, `)`, `\\`, `/`, `~`]) {
		return path
	}
	if relative.contains('../..') || relative.contains('..\\..') {
		return path
	}
	return '<tsconfigRootDir>/${relative}'
}

// node_relative is Node's path.relative of two absolute paths: the path from `from` to `to`, with
// `..` for each directory of `from` after the part they share; '' for the same path. On Windows
// the names are compared without case, a path on another drive is `to` itself, and the result has
// `\`.
fn node_relative(from string, to string) string {
	sep := os.path_separator
	a := os.norm_path(from).split(sep).filter(it != '')
	b := os.norm_path(to).split(sep).filter(it != '')
	mut common := 0
	for common < a.len && common < b.len {
		same := $if windows {
			a[common].to_lower() == b[common].to_lower()
		} $else {
			a[common] == b[common]
		}
		if !same {
			break
		}
		common++
	}
	$if windows {
		if common == 0 {
			return os.norm_path(to)
		}
	}
	mut parts := []string{}
	for _ in common .. a.len {
		parts << '..'
	}
	parts << b[common..]
	return parts.join(sep)
}

// json_stringify is a string as JavaScript's JSON.stringify writes it: `"` and `\` escaped, and
// the control characters as their short escape or as `\u00XX`.
fn json_stringify(s string) string {
	mut out := strings.new_builder(s.len + 2)
	out.write_u8(`"`)
	for c in s {
		match c {
			`"` { out.write_string('\\"') }
			`\\` { out.write_string('\\\\') }
			`\b` { out.write_string('\\b') }
			`\f` { out.write_string('\\f') }
			`\n` { out.write_string('\\n') }
			`\r` { out.write_string('\\r') }
			`\t` { out.write_string('\\t') }
			else {
				if c < 0x20 {
					out.write_string('\\u00${c:02x}')
				} else {
					out.write_u8(c)
				}
			}
		}
	}
	out.write_u8(`"`)
	return out.str()
}

// fatal_report is what a file with ESLint's parsing error prints: `Parsing error: ` and the
// parser's message at 0:0, without an end (ESLint gives the parser's error no location).
fn fatal_report(path string, message string) FileReport {
	return FileReport{
		stdout:   '${path}:0:0\t${rules.problem_rule}\tfatal\t${tsv_field('Parsing error: ' + message.trim_space())}\n'
		problems: 1
	}
}

// fatal_finding is that error as a finding, for --summary.
fn fatal_finding(message string) rules.Finding {
	return rules.Finding{
		rule:       rules.problem_rule
		message_id: 'fatal'
		text:       'Parsing error: ${message.trim_space()}'
	}
}
