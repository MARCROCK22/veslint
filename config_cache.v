module main

import crypto.sha256
import json2
import os
import time

// The cache of resolved configurations. Resolving an ESLint configuration starts bun, which loads
// ESLint and every plugin the configuration imports: more than a second for a usual one, often
// more than the lint itself. What ESLint resolved is saved in `node_modules/.cache/veslint` (the
// closest node_modules from the configuration up; without one nothing is saved) and used again
// while nothing it came from changed:
//
// - the key of an entry: the version of veslint and the resolver script, the configuration, the
//   mode (given or looked up), the working directory, VESLINT_ESLINT_DIR and the files to lint, in
//   their order (the resolved JSON lists them so);
// - in the entry: every file the resolution read (the configuration, the modules it imported,
//   ESLint and the plugins, and what was read through fs, such as a .gitignore) and bun itself,
//   each with its size, times and inode, and the small ones of the project with the hash of their
//   content (file_stamp); the environment variables it read, with their values; and with lookup,
//   the closest eslint.config.* of the directory of each file (a new one in a subdirectory changes
//   which applies).
//
// A resolution ESLint rejects is not saved. VESLINT_CONFIG_CACHE=0 turns the cache off.
//
// ESLint resolves each file on its own, so the resolution of some files is in a resolution of more
// files with the same configuration, mode, directory and VESLINT_ESLINT_DIR (the part of the key
// without the files, which starts the entry's name): a request of the server, for a file or a few,
// takes it out of the entry of a run of the command line on the project (subset_resolution), with
// what the resolver tells of each file (what it adds to `pluginRules`, `typescriptEslint` and
// `ruleDefaults`), instead of starting bun.

const config_cache_entry_version = 2

// Entries not used for this long are removed when another one is written.
const config_cache_max_age = 30 * 24 * time.hour

// ResolutionMemo keeps, in a process that resolves the same configuration for the same files
// again and again (veslint --server, at every edit), each resolution by the name of the entry of
// its files, with the entry it came from, decoded: the next resolution only checks that nothing it
// came from changed (DecodedEntry.valid), without reading and decoding the entry again. It also
// keeps the name of the entry of each request's files and the configuration loaded from each
// resolution (load_config_resolving).
struct ResolutionMemo {
mut:
	entries map[string]MemoizedResolution
	// sources: the entries the resolutions came from, by path (one of more files serves many)
	sources map[string]&DecodedEntry
	// paths: the name of the entry of the files of a configuration (entry_key). It is made of the
	// version, the configuration, the files, the directory of the process and an environment
	// variable (config_cache_parts), which do not change in a process, and of the cache's
	// directory, the closest node_modules: one made closer later is not looked at, which changes
	// where the resolution is saved, not what it is.
	paths map[string]string
	// loaded: the configuration loaded from a resolution for the configuration and the files as
	// given (loaded_config)
	loaded map[string]&MemoizedConfig
}

// DecodedEntry is an entry of the cache, decoded, with the stamps of its inputs read once.
@[heap]
struct DecodedEntry {
	entry  map[string]json2.Any
	inputs []InputStamp
	broken bool // an input without its path or its stamp: never valid, as for entry_valid
}

// InputStamp is the stamp of an input of an entry (file_stamp), with its parts as numbers when it
// has them, so that a check stats the file and compares numbers.
struct InputStamp {
	path   string
	stamp  string
	parsed bool // size, mtime, ctime and inode are those of `stamp`
	size   u64
	mtime  i64
	ctime  i64
	inode  u64
	hash   string // the hash of the content, for a file of the project ('' for none)
}

struct MemoizedResolution {
	resolved string
	source   string // the entry it came from: of these files, or of more (reuse)
	used     i64    // when `source` was last marked as used (touch_entry)
}

@[heap]
struct MemoizedConfig {
	resolved string
	loaded   LoadedConfig
}

// memo_resolutions is how many resolutions a ResolutionMemo keeps before it starts again.
const memo_resolutions = 64

// decoded_entry reads the stamps of the inputs of `entry`.
fn decoded_entry(entry map[string]json2.Any) &DecodedEntry {
	mut inputs := []InputStamp{}
	mut broken := false
	if listed := entry['inputs'] {
		for item in listed.as_array() {
			input := item.as_map()
			if 'path' !in input || 'stamp' !in input {
				broken = true
				continue
			}
			path := (input['path'] or { json2.Any('') }).str()
			stamp := (input['stamp'] or { json2.Any('') }).str()
			parts := stamp.split(':')
			if parts.len == 4 || parts.len == 5 {
				inputs << InputStamp{
					path:   path
					stamp:  stamp
					parsed: true
					size:   parts[0].u64()
					mtime:  parts[1].i64()
					ctime:  parts[2].i64()
					inode:  parts[3].u64()
					hash:   if parts.len == 5 { parts[4] } else { '' }
				}
			} else {
				inputs << InputStamp{
					path:  path
					stamp: stamp
				}
			}
		}
	}
	return &DecodedEntry{
		entry:  entry
		inputs: inputs
		broken: broken
	}
}

// valid is entry_valid for the decoded entry: an input whose stamp has its parts is checked with
// one stat, and with its content when the stamp has its hash (file_stamp); another with file_stamp.
fn (d &DecodedEntry) valid(files []string, lookup bool) bool {
	if d.broken || 'inputs' !in d.entry {
		return false
	}
	for input in d.inputs {
		if !input.parsed {
			if file_stamp(input.path) != input.stamp {
				return false
			}
			continue
		}
		info := os.stat(input.path) or { return false }
		if info.get_filetype() == .directory || info.size != input.size
			|| info.mtime != input.mtime || info.ctime != input.ctime || info.inode != input.inode {
			return false
		}
		if input.hash != '' || (info.size <= config_cache_hashed_size
			&& !input.path.contains('${os.path_separator}node_modules${os.path_separator}')) {
			// The content counts (file_stamp): the same stamp then.
			if file_stamp(input.path) != input.stamp {
				return false
			}
		}
	}
	return entry_environment_valid(d.entry, files, lookup)
}

// keep remembers the resolution of the entry `entry_path` out of `source`.
fn (mut m ResolutionMemo) keep(entry_path string, resolved string, source string, entry map[string]json2.Any) {
	if m.entries.len >= memo_resolutions {
		m.entries = map[string]MemoizedResolution{}
		m.sources = map[string]&DecodedEntry{}
	}
	m.entries[entry_path] = MemoizedResolution{
		resolved: resolved
		source:   source
		used:     time.now().unix()
	}
	m.sources[source] = decoded_entry(entry)
}

// mark_used marks the entry a kept resolution came from as used, now and then: entries not used
// for a month are removed.
fn (mut m ResolutionMemo) mark_used(entry_path string) {
	kept := m.entries[entry_path] or { return }
	now := time.now().unix()
	if now - kept.used > 3600 {
		touch_entry(kept.source)
		m.entries[entry_path] = MemoizedResolution{
			...kept
			used: now
		}
	}
}

fn entry_key(config_path string, files []string, lookup bool) string {
	return '${lookup}\0${config_path}\0${files.join('\0')}'
}

// loaded_config is the configuration loaded from `resolved` for `files` (as given) of the
// configuration `path` (as given), when the memo has it.
fn (m &ResolutionMemo) loaded_config(resolved string, path string, files []string) ?LoadedConfig {
	kept := m.loaded['${path}\0${files.join('\0')}'] or { return none }
	if kept.resolved != resolved {
		return none
	}
	return kept.loaded
}

fn (mut m ResolutionMemo) keep_loaded(resolved string, path string, files []string, loaded LoadedConfig) {
	if m.loaded.len >= memo_resolutions {
		m.loaded = map[string]&MemoizedConfig{}
	}
	m.loaded['${path}\0${files.join('\0')}'] = &MemoizedConfig{
		resolved: resolved
		loaded:   loaded
	}
}

// config_entry_path is the path of the entry of a resolution in `dir`, the cache's directory.
fn config_entry_path(dir string, base string, config_path string, files []string, lookup bool) string {
	return os.join_path(dir, 'config-${base}-${config_cache_key(config_path, files, lookup)}.json')
}

// resolve_cached is resolve_with_bun through the cache; with `reuse` (and without lookup), out of
// the entry of more files when there is no entry of these files. With a `memo`, out of a
// resolution it keeps while it is valid.
fn resolve_cached(config_path string, files []string, lookup bool, reuse bool, mut memo ResolutionMemo) !string {
	if os.getenv('VESLINT_CONFIG_CACHE') == '0' {
		return resolve_with_bun(config_path, files, lookup)
	}
	request_key := entry_key(config_path, files, lookup)
	if entry_path := memo.paths[request_key] {
		if kept := memo.entries[entry_path] {
			source := memo.sources[kept.source] or { &DecodedEntry{} }
			if source.valid(files, lookup) {
				memo.mark_used(entry_path)
				return kept.resolved
			}
			memo.entries.delete(entry_path)
		}
	}
	dir := config_cache_dir(config_path) or { return resolve_with_bun(config_path, files, lookup) }
	base := config_cache_base(config_path, lookup)
	entry_path := config_entry_path(dir, base, config_path, files, lookup)
	if memo.paths.len >= memo_resolutions {
		memo.paths = map[string]string{}
	}
	memo.paths[request_key] = entry_path
	if entry := read_entry(entry_path) {
		if entry_valid(entry, files, lookup) {
			if resolved := entry['resolved'] {
				touch_entry(entry_path)
				memo.keep(entry_path, resolved.str(), entry_path, entry)
				return resolved.str()
			}
		}
	}
	if reuse && !lookup {
		if resolved, source, entry := subset_resolution(dir, base, files) {
			memo.keep(entry_path, resolved, source, entry)
			return resolved
		}
	}
	inputs_path := os.join_path(os.temp_dir(), 'veslint-inputs-${os.getpid()}.json')
	defer {
		os.rm(inputs_path) or {}
	}
	resolved := resolve_with_bun_inputs(config_path, files, lookup, inputs_path)!
	inputs := os.read_file(inputs_path) or { return resolved }
	save_resolution(dir, entry_path, files, lookup, resolved, inputs)
	return resolved
}

// config_cache_dir is `.cache/veslint` in the closest node_modules from the directory of the
// configuration up.
fn config_cache_dir(config_path string) ?string {
	mut current := os.dir(config_path)
	for {
		modules := os.join_path(current, 'node_modules')
		if os.is_dir(modules) {
			return os.join_path(modules, '.cache', 'veslint')
		}
		parent := os.dir(current)
		if parent == current || !os.is_abs_path(parent) {
			return none
		}
		current = parent
	}
	return none
}

// touch_entry marks an entry as used, so that it is not removed as unused.
fn touch_entry(entry_path string) {
	now := int(time.now().unix())
	os.utime(entry_path, now, now) or {}
}

// config_cache_key names the entry of a resolution (see the comment at the top).
fn config_cache_key(config_path string, files []string, lookup bool) string {
	return sha256.hexhash(config_cache_parts(config_path, lookup).join('\0') + '\0' +
		files.join('\n'))[..32]
}

// config_cache_base is the part of the key without the files.
fn config_cache_base(config_path string, lookup bool) string {
	return sha256.hexhash(config_cache_parts(config_path, lookup).join('\0'))[..16]
}

fn config_cache_parts(config_path string, lookup bool) []string {
	return [
		'veslint ${version}',
		sha256.hexhash(eslint_resolver),
		config_path,
		if lookup { 'lookup' } else { 'config' },
		os.getwd(),
		os.getenv('VESLINT_ESLINT_DIR'),
	]
}

// read_entry is the object of an entry of this version of the cache.
fn read_entry(entry_path string) ?map[string]json2.Any {
	text := os.read_file(entry_path) or { return none }
	root := json2.decode[json2.Any](text) or { return none }
	if root !is map[string]json2.Any {
		return none
	}
	entry := root.as_map()
	if (entry['version'] or { return none }).int() != config_cache_entry_version {
		return none
	}
	return entry
}

// entry_valid: nothing the resolution of the entry came from changed (for `files`, with lookup).
fn entry_valid(entry map[string]json2.Any, files []string, lookup bool) bool {
	for item in (entry['inputs'] or { return false }).as_array() {
		input := item.as_map()
		path := (input['path'] or { return false }).str()
		if file_stamp(path) != (input['stamp'] or { return false }).str() {
			return false
		}
	}
	return entry_environment_valid(entry, files, lookup)
}

// entry_environment_valid: the environment variables the resolution of the entry read have the
// values they had, and with lookup, `files` have the closest configurations they had.
fn entry_environment_valid(entry map[string]json2.Any, files []string, lookup bool) bool {
	for name, value in (entry['env'] or { return false }).as_map() {
		current := os.getenv_opt(name)
		if value is json2.Null {
			if current != none {
				return false
			}
		} else if (current or { return false }) != value.str() {
			return false
		}
	}
	if lookup && config_lookups(files) != (entry['lookups'] or { return false }).str() {
		return false
	}
	return true
}

// subset_resolution is the resolution of `files` out of a valid entry with the same base that has
// them all, the most recently used first (see the comment at the top); none when there is none.
// What it gives is what bun would print for them: the configurations of the files in the order
// they first come, the files in their order, and of `pluginRules` and `ruleDefaults` the ones the
// files add, in the order of the entry (the order bun sorts them in).
fn subset_resolution(dir string, base string, files []string) ?(string, string, map[string]json2.Any) {
	prefix := 'config-${base}-'
	mut names := (os.ls(dir) or { return none }).filter(it.starts_with(prefix)
		&& it.ends_with('.json'))
	mut used := map[string]i64{}
	for name in names {
		used[name] = os.file_last_mod_unix(os.join_path(dir, name))
	}
	names.sort_with_compare(fn [used] (a &string, b &string) int {
		ua, ub := used[*a], used[*b]
		return if ua > ub {
			-1
		} else if ua < ub {
			1
		} else {
			compare_strings(a, b)
		}
	})
	for name in names {
		path := os.join_path(dir, name)
		entry := read_entry(path) or { continue }
		listed := (entry['files'] or { continue }).as_array().map(it.str())
		mut index := map[string]int{}
		for i, file in listed {
			if file !in index {
				index[file] = i
			}
		}
		if files.any(it !in index) || !entry_valid(entry, files, false) {
			continue
		}
		resolved := compose_resolution(entry, index, files) or { continue }
		touch_entry(path)
		return resolved, path, entry
	}
	return none
}

// compose_resolution writes the resolved JSON of `files` (each at its place in `index`) out of the
// entry's resolution of more files, with the parts the resolver gave for each of them.
fn compose_resolution(entry map[string]json2.Any, index map[string]int, files []string) ?string {
	resolved := (entry['resolved'] or { return none }).str()
	parts := (entry['parts'] or { return none }).as_array()
	file_parts := (entry['file_parts'] or { return none }).as_array().map(it.int())
	members := json_members(resolved, 0)?
	if 'error' in members {
		return none
	}
	config_spans := json_elements(resolved, (members['configs'] or { return none }).value)?
	file_spans := json_elements(resolved, (members['files'] or { return none }).value)?
	plugin_spans := json_elements(resolved, (members['pluginRules'] or { return none }).value)?
	if file_spans.len != file_parts.len {
		return none
	}
	mut configs := []string{}
	mut renumbered := map[int]int{}
	mut entries := []string{}
	mut plugin_rules := map[string]bool{}
	mut typescript_eslint := false
	mut defaults := map[string]string{}
	for file in files {
		i := index[file] or { return none }
		text := resolved[file_spans[i].start..file_spans[i].end]
		fields := json_members(text, 0)?
		config := (
			fields['config'] or {
				// A file ESLint does not lint: its message.
				entries << text
				continue
			}
		).value
		old := text[config.start..config.end].int()
		if old !in renumbered {
			if old < 0 || old >= config_spans.len {
				return none
			}
			renumbered[old] = configs.len
			configs << resolved[config_spans[old].start..config_spans[old].end]
		}
		path := (fields['path'] or { return none }).value
		mut out := '{"path":${text[path.start..path.end]},"config":${renumbered[old]}'
		if runes := fields['svelteConfigRunes'] {
			out += ',"svelteConfigRunes":${text[runes.value.start..runes.value.end]}'
		}
		if default_project := fields['defaultProject'] {
			out += ',"defaultProject":${text[default_project.value.start..default_project.value.end]}'
		}
		entries << out + '}'
		p := file_parts[i]
		if p < 0 || p >= parts.len {
			return none
		}
		part := parts[p].as_map()
		for name in (part['pluginRules'] or { return none }).as_array() {
			plugin_rules[name.str()] = true
		}
		if (part['typescriptEslint'] or { return none }).bool() {
			typescript_eslint = true
		}
		for id, value in (part['ruleDefaults'] or { return none }).as_map() {
			defaults[id] = value.str()
		}
	}
	mut plugins := []string{}
	for span in plugin_spans {
		raw := resolved[span.start..span.end]
		name := json_string(raw)?
		if name in plugin_rules {
			plugins << raw
		}
	}
	if plugins.len != plugin_rules.len {
		return none
	}
	eslint := (members['eslint'] or { return none }).value
	mut out := '{"eslint":${resolved[eslint.start..eslint.end]},"pluginRules":[${plugins.join(',')}],"typescriptEslint":${typescript_eslint},"configs":[${configs.join(',')}],"files":[${entries.join(',')}]'
	if defaults.len > 0 {
		all := (members['ruleDefaults'] or { return none }).value
		text := resolved[all.start..all.end]
		mut kept := []string{}
		for id, member in json_members(text, 0)? {
			if value := defaults[id] {
				kept << '${text[member.key.start..member.key.end]}:${value}'
			}
		}
		if kept.len != defaults.len {
			return none
		}
		out += ',"ruleDefaults":{${kept.join(',')}}'
	}
	return out + '}'
}

// save_resolution writes the entry of a resolution, with what the resolver says it read, unless
// ESLint rejected the configuration. A failure to write it is not an error: the cache only makes
// the next run faster.
fn save_resolution(dir string, entry_path string, files []string, lookup bool, resolved string, inputs_text string) {
	parsed := json2.decode[json2.Any](resolved) or { return }
	if parsed !is map[string]json2.Any || 'error' in parsed.as_map() {
		return
	}
	inputs := json2.decode[json2.Any](inputs_text) or { return }
	if inputs !is map[string]json2.Any {
		return
	}
	mut read := (inputs.as_map()['files'] or { json2.Any([]json2.Any{}) }).as_array().map(it.str())
	if bun := os.find_abs_path_of_executable('bun') {
		read << os.real_path(bun)
	}
	mut stamps := []json2.Any{}
	for path in read {
		stamp := file_stamp(path)
		if stamp == '' {
			continue
		}
		stamps << json2.Any({
			'path':  json2.Any(path)
			'stamp': json2.Any(stamp)
		})
	}
	mut entry := map[string]json2.Any{}
	entry['version'] = json2.Any(config_cache_entry_version)
	entry['inputs'] = json2.Any(stamps)
	entry['env'] = inputs.as_map()['env'] or { json2.Any(map[string]json2.Any{}) }
	// What subset_resolution needs to take some of the files out of this resolution.
	entry['files'] = json2.Any(files.map(json2.Any(it)))
	entry['parts'] = inputs.as_map()['parts'] or { json2.Any([]json2.Any{}) }
	entry['file_parts'] = inputs.as_map()['fileParts'] or { json2.Any([]json2.Any{}) }
	if lookup {
		entry['lookups'] = json2.Any(config_lookups(files))
	}
	entry['resolved'] = json2.Any(resolved)
	os.mkdir_all(dir) or { return }
	prune_config_cache(dir)
	// Written whole, then renamed: a run that reads it at the same time sees the old entry or the
	// new one.
	partial := '${entry_path}.${os.getpid()}.tmp'
	os.write_file(partial, json2.encode(json2.Any(entry))) or { return }
	os.mv(partial, entry_path) or { os.rm(partial) or {} }
}

// JsonSpan is where a value is in a JSON text: text[start..end].
struct JsonSpan {
	start int
	end   int
}

// JsonMember is a member of a JSON object: its key and its value.
struct JsonMember {
	key   JsonSpan
	value JsonSpan
}

// json_members are the members of the JSON object at `at`, by their key, in their order; none if
// it is not an object.
fn json_members(text string, at int) ?map[string]JsonMember {
	mut i := json_skip_space(text, at)
	if i >= text.len || text[i] != `{` {
		return none
	}
	mut out := map[string]JsonMember{}
	i = json_skip_space(text, i + 1)
	if i < text.len && text[i] == `}` {
		return out
	}
	for {
		key_start := i
		key_end := json_value_end(text, key_start)?
		key := json_string(text[key_start..key_end])?
		i = json_skip_space(text, key_end)
		if i >= text.len || text[i] != `:` {
			return none
		}
		start := json_skip_space(text, i + 1)
		end := json_value_end(text, start)?
		if key !in out {
			out[key] = JsonMember{JsonSpan{key_start, key_end}, JsonSpan{start, end}}
		}
		i = json_skip_space(text, end)
		if i < text.len && text[i] == `,` {
			i = json_skip_space(text, i + 1)
			continue
		}
		if i < text.len && text[i] == `}` {
			return out
		}
		return none
	}
	return none
}

// json_elements are the elements of the JSON array at `span`.
fn json_elements(text string, span JsonSpan) ?[]JsonSpan {
	mut i := json_skip_space(text, span.start)
	if i >= text.len || text[i] != `[` {
		return none
	}
	mut out := []JsonSpan{}
	i = json_skip_space(text, i + 1)
	if i < text.len && text[i] == `]` {
		return out
	}
	for {
		end := json_value_end(text, i)?
		out << JsonSpan{i, end}
		i = json_skip_space(text, end)
		if i < text.len && text[i] == `,` {
			i = json_skip_space(text, i + 1)
			continue
		}
		if i < text.len && text[i] == `]` {
			return out
		}
		return none
	}
	return none
}

fn json_skip_space(text string, at int) int {
	mut i := at
	for i < text.len && text[i] in [` `, `\t`, `\n`, `\r`] {
		i++
	}
	return i
}

// json_value_end is where the JSON value that starts at `at` ends.
fn json_value_end(text string, at int) ?int {
	if at >= text.len {
		return none
	}
	match text[at] {
		`"` {
			mut i := at + 1
			for i < text.len {
				if text[i] == `\\` {
					i += 2
					continue
				}
				if text[i] == `"` {
					return i + 1
				}
				i++
			}
			return none
		}
		`{`, `[` {
			mut depth := 0
			mut i := at
			for i < text.len {
				c := text[i]
				if c == `"` {
					i = json_value_end(text, i)?
					continue
				}
				if c == `{` || c == `[` {
					depth++
				} else if c == `}` || c == `]` {
					depth--
					if depth == 0 {
						return i + 1
					}
				}
				i++
			}
			return none
		}
		else {
			mut i := at
			for i < text.len && text[i] !in [`,`, `}`, `]`, ` `, `\t`, `\n`, `\r`] {
				i++
			}
			return if i > at { i } else { none }
		}
	}
}

// json_string is the value of a JSON string.
fn json_string(raw string) ?string {
	value := json2.decode[json2.Any](raw) or { return none }
	if value !is string {
		return none
	}
	return value.str()
}

// Files outside node_modules up to this size are also told apart by their content.
const config_cache_hashed_size = u64(1024 * 1024)

// file_stamp tells a file apart from what it was: its size, times and inode, and for a file of
// the project (outside node_modules, not bigger than config_cache_hashed_size) the hash of its
// content too, so that a change in the same second, of the same size, is still seen. Empty when it
// is not a file that can be read.
fn file_stamp(path string) string {
	// One stat: os.is_file would make two more.
	info := os.stat(path) or { return '' }
	if info.get_filetype() == .directory {
		return ''
	}
	mut stamp := '${info.size}:${info.mtime}:${info.ctime}:${info.inode}'
	if info.size <= config_cache_hashed_size
		&& !path.contains('${os.path_separator}node_modules${os.path_separator}') {
		content := os.read_file(path) or { return '' }
		stamp += ':' + sha256.hexhash(content)
	}
	return stamp
}

// config_lookups is the closest eslint.config.* of the directory of each file, which ESLint
// finds for it in lookup mode.
fn config_lookups(files []string) string {
	mut seen := map[string]bool{}
	mut lines := []string{}
	for file in files {
		dir := os.dir(file)
		if dir in seen {
			continue
		}
		seen[dir] = true
		lines << '${dir}\t${find_flat_config(dir) or { '' }}'
	}
	return lines.join('\n')
}

// prune_config_cache removes the entries not used for config_cache_max_age.
fn prune_config_cache(dir string) {
	oldest := time.now().unix() - i64(config_cache_max_age / time.second)
	for name in os.ls(dir) or { return } {
		if !name.starts_with('config-') {
			continue
		}
		path := os.join_path(dir, name)
		if os.file_last_mod_unix(path) < oldest {
			os.rm(path) or {}
		}
	}
}
