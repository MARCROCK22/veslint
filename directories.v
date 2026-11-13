module main

import os

// Directories on the command line (`veslint .`, `veslint src`): veslint lists the TypeScript files
// under each one as ESLint walks a directory, and ESLint's configuration then drops the ones it
// does not lint (see parse_args).

// typescript_extensions are the extensions of the files a directory brings.
const typescript_extensions = ['.ts', '.mts', '.cts', '.tsx']

// directory_files lists the TypeScript files under `dir`, sorted, each as `dir` joined to its path
// inside it (`.` is left out: `veslint .` prints `src/a.ts`). The directories ESLint never enters
// by default (`node_modules` and `.git`, its default ignores) are not entered, and neither are
// symbolic links to directories, which could make a cycle.
fn directory_files(dir string) []string {
	mut out := []string{}
	mut pending := [dir]
	for pending.len > 0 {
		current := pending.pop()
		entries := os.ls(current) or { continue }
		for name in entries {
			path := if current == '.' { name } else { os.join_path(current, name) }
			if os.is_dir(path) {
				if name !in ['node_modules', '.git'] && !os.is_link(path) {
					pending << path
				}
			} else if os.file_ext(name).to_lower() in typescript_extensions {
				out << path
			}
		}
	}
	out.sort()
	return out
}

// flat_config_names are the configuration files ESLint 10 looks for, in its order
// (FLAT_CONFIG_FILENAMES of lib/config/config-loader.js).
const flat_config_names = ['eslint.config.js', 'eslint.config.mjs', 'eslint.config.cjs',
	'eslint.config.ts', 'eslint.config.mts', 'eslint.config.cts']

// find_flat_config is the closest ESLint configuration file from the directory `from` up, as
// ESLint looks for one; none if there is none.
fn find_flat_config(from string) ?string {
	mut dir := os.abs_path(from)
	for {
		for name in flat_config_names {
			path := os.join_path(dir, name)
			if os.is_file(path) {
				return path
			}
		}
		parent := os.dir(dir)
		if parent == dir || parent == '' {
			return none
		}
		dir = parent
	}
	return none
}
