module tsgo

import json2

// What the `no-deep-imports` rule of @slipher/eslint-plugin needs from tsgo: the file a module name
// resolves to from a directory, with the options of a project (ts.resolveModuleName with the
// options of the program), and the names that file exports as a module
// (checker.getExportsOfModule), with the program of the project or, when the file is not one of
// its files, with a program of its own (ts.createProgram with those options, noEmit and
// skipLibCheck). Like the plugin, the client keeps the names of each file for its whole life.

// project_options_json is the JSON of the compiler options of a tsconfig (parseConfigFile), as
// tsgo sends them: what createModuleResolver and the programs of a snapshot take. An inferred
// project, which has no tsconfig, has none.
fn (mut c Client) project_options_json(tsconfig string) !string {
	if !tsconfig.ends_with('.json') {
		return '{}'
	}
	response := c.request('parseConfigFile', json2.encode(ParseConfigFileParams{
		file: tsconfig
	}))!
	root := json2.decode[json2.Any](response)!
	options := root.as_map()['options'] or { return '{}' }
	return options.json_str()
}

// resolve_module_name is the file `name` resolves to from a file of `directory`, with the options
// of the project `tsconfig`, as it is on disk; '' when it does not resolve.
pub fn (mut c Client) resolve_module_name(tsconfig string, name string, directory string) !string {
	if tsconfig !in c.module_resolvers {
		options := c.project_options_json(tsconfig)!
		c.module_resolvers[tsconfig] = c.request('createModuleResolver',
			'{"compilerOptions":${options}}')!.trim_space().int()
	}
	params := '{"resolver":${c.module_resolvers[tsconfig]},"moduleName":${json2.encode(name)},"containingDirectory":${json2.encode(directory)}}'
	response := json2.decode[json2.Any](c.request('resolveModuleName', params)!)!
	resolved := response.as_map()['resolvedModule'] or { return '' }
	file := resolved.as_map()['resolvedFileName'] or { return '' }
	return file.str()
}

// module_export_names are the names `file` exports as a module, asked once for each file.
pub fn (mut c Client) module_export_names(snapshot int, project string, file string) ![]string {
	if file !in c.module_exports {
		c.module_exports[file] = c.ask_module_export_names(snapshot, project, file)!
	}
	return c.module_exports[file]
}

fn (mut c Client) ask_module_export_names(snapshot int, project string, file string) ![]string {
	file_params := '{"snapshot":${snapshot},"project":${json2.encode(project)},"file":${json2.encode(file)}}'
	// tsgo rejects a file that is not in the program.
	if symbol := c.symbol_request(snapshot, 'getSymbolOfSourceFile', file_params) {
		if !symbol.is_null() {
			return c.export_names(snapshot, project, symbol.id)!
		}
	}
	// A program of its own, in a snapshot made for it and released after.
	mut options := json2.decode[json2.Any](c.project_options_json(project)!)!.as_map()
	options['noEmit'] = json2.Any(true)
	options['skipLibCheck'] = json2.Any(true)
	program_params := '{"snapshot":${snapshot},"changes":{"createPrograms":[{"rootFiles":[${json2.encode(file)}],"compilerOptions":${json2.Any(options).json_str()}}]}}'
	response := json2.decode[json2.Any](c.request('updateSnapshot', program_params)!)!.as_map()
	program_snapshot := (response['snapshot'] or { return []string{} }).int()
	operation := (response['operation'] or { return []string{} }).as_map()
	created := (operation['createdPrograms'] or { return []string{} }).as_array()
	if program_snapshot == snapshot {
		return []string{}
	}
	defer {
		c.release_snapshot(program_snapshot) or {}
	}
	if created.len == 0 {
		return []string{}
	}
	program := created[0].str()
	symbol := c.symbol_request(program_snapshot, 'getSymbolOfSourceFile', '{"snapshot":${program_snapshot},"project":${json2.encode(program)},"file":${json2.encode(file)}}') or {
		return []string{}
	}
	if symbol.is_null() {
		return []string{}
	}
	return c.export_names(program_snapshot, program, symbol.id)!
}

// export_names are the names of getExportsOfModule of a module symbol, unescaped.
fn (mut c Client) export_names(snapshot int, project string, symbol_id int) ![]string {
	symbols := c.symbols_request(snapshot, 'getExportsOfModule', c.symbol_params(snapshot,
		project, symbol_id)!)!
	return symbols.map(if it.name.starts_with('___') { it.name[1..] } else { it.name })
}

// source_file_names are the files of the program of a project (getSourceFileNames), asked once for
// each snapshot and project: the `group-exists` rule looks only at files the program has
// (program.getSourceFile).
pub fn (mut c Client) source_file_names(snapshot int, project string) ![]string {
	key := '${snapshot}:${project}'
	if key !in c.program_files {
		names := json2.decode[[]string](c.request('getSourceFileNames', '{"snapshot":${snapshot},"project":${json2.encode(project)}}')!)!
		c.program_files[key] = names
	}
	return c.program_files[key]
}
