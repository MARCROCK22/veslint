module tsgo

import os
import time

// A virtual file (start_virtual): not on disk, yet part of the project through the `include` of its
// tsconfig, with the types of its served text. It is how a .vue gets types: its TypeScript twin.
fn test_virtual_file_is_in_the_project() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-twin-${os.getpid()}')
	os.mkdir_all(os.join_path(dir, 'src')) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["src/**/*.ts"]}') or { panic(err) }
	os.write_file(os.join_path(dir, 'src/main.ts'), 'export const m: number = 1;\n') or { panic(err) }
	twin := os.join_path(dir, 'src/App.vue.vls.ts')
	text := 'import { m } from "./main";\nconst count = m;\nexport {};\n'
	mut c := start_virtual(bin, dir, 20 * time.second, map[string]string{}, {
		twin: text
	}) or { panic(err) }
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	project := snap.projects[0].id
	pos := text.index('count') or { 0 }
	symbols := c.symbols_at(snap.snapshot, project, twin, [pos]) or { panic(err) }
	types := c.types_at(snap.snapshot, project, twin, [pos]) or { panic(err) }
	got := c.type_to_string(snap.snapshot, project, types[0].id) or { 'err' }
	c.shutdown()
	assert symbols[0].name == 'count'
	assert got == 'number'
	assert !os.exists(twin)
}
