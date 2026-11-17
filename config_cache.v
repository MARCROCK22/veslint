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

const config_cache_entry_version = 1

// Entries not used for this long are removed when another one is written.
const config_cache_max_age = 30 * 24 * time.hour

// resolve_cached is resolve_with_bun through the cache.
fn resolve_cached(config_path string, files []string, lookup bool) !string {
	if os.getenv('VESLINT_CONFIG_CACHE') == '0' {
		return resolve_with_bun(config_path, files, lookup)
	}
	dir := config_cache_dir(config_path) or { return resolve_with_bun(config_path, files, lookup) }
	entry_path := os.join_path(dir, 'config-${config_cache_key(config_path, files, lookup)}.json')
	if resolved := cached_resolution(entry_path, files, lookup) {
		// Touched, so that it is not removed as unused.
		now := int(time.now().unix())
		os.utime(entry_path, now, now) or {}
		return resolved
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

// config_cache_key names the entry of a resolution (see the comment at the top).
fn config_cache_key(config_path string, files []string, lookup bool) string {
	parts := [
		'veslint ${version}',
		sha256.hexhash(eslint_resolver),
		config_path,
		if lookup { 'lookup' } else { 'config' },
		os.getwd(),
		os.getenv('VESLINT_ESLINT_DIR'),
		files.join('\n'),
	]
	return sha256.hexhash(parts.join('\0'))[..32]
}

// cached_resolution is the resolved JSON of the entry when nothing it came from changed.
fn cached_resolution(entry_path string, files []string, lookup bool) ?string {
	text := os.read_file(entry_path) or { return none }
	root := json2.decode[json2.Any](text) or { return none }
	if root !is map[string]json2.Any {
		return none
	}
	entry := root.as_map()
	if (entry['version'] or { return none }).int() != config_cache_entry_version {
		return none
	}
	for item in (entry['inputs'] or { return none }).as_array() {
		input := item.as_map()
		path := (input['path'] or { return none }).str()
		if file_stamp(path) != (input['stamp'] or { return none }).str() {
			return none
		}
	}
	for name, value in (entry['env'] or { return none }).as_map() {
		current := os.getenv_opt(name)
		if value is json2.Null {
			if current != none {
				return none
			}
		} else if (current or { return none }) != value.str() {
			return none
		}
	}
	if lookup && config_lookups(files) != (entry['lookups'] or { return none }).str() {
		return none
	}
	resolved := entry['resolved'] or { return none }
	return resolved.str()
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

// Files outside node_modules up to this size are also told apart by their content.
const config_cache_hashed_size = u64(1024 * 1024)

// file_stamp tells a file apart from what it was: its size, times and inode, and for a file of
// the project (outside node_modules, not bigger than config_cache_hashed_size) the hash of its
// content too, so that a change in the same second, of the same size, is still seen. Empty when it
// is not a file that can be read.
fn file_stamp(path string) string {
	if !os.is_file(path) {
		return ''
	}
	info := os.stat(path) or { return '' }
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
