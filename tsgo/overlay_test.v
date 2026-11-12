module tsgo

import os
import time

// With a real tsgo: a file that is not valid UTF-8 is read by tsgo as the text it is served, and
// from disk without it. `/* a<E2 82>b */ const x = 1;` has a truncated sequence, which Node (and
// so ESLint) decodes as one U+FFFD and tsgo, reading the bytes itself, counts as two units: the
// position of `x` in the decoded text only has the symbol `x` when tsgo is given that text.
fn test_tsgo_reads_the_served_text() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-overlay-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	file := os.join_path(dir, 'a.ts')
	other := os.join_path(dir, 'b.ts')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(file, '/* a\xE2\x82b */ const x = 1;\nexport {};\n') or { panic(err) }
	os.write_file(other, 'export const fromDisk = "y";\n') or { panic(err) }
	// The text Node decodes: a quote, a backslash, a line break and a NUL in it reach tsgo too.
	served := '/* a\xEF\xBF\xBDb */ const x = 1;\nexport {};\n'
	x := served.index('x') or { panic('no x') } - 2 // U+FFFD is 3 bytes and 1 UTF-16 unit

	mut plain := start(bin, dir, 20 * time.second) or { panic(err) }
	plain.initialize() or { panic(err) }
	plain_snap := plain.create_snapshot([tsconfig]) or { panic(err) }
	from_disk := plain.symbols_at(plain_snap.snapshot, plain_snap.projects[0].id, file,
		[x]) or { panic(err) }
	plain.shutdown()
	assert from_disk[0].is_null(), 'tsgo reading the bytes found `${from_disk[0].name}` at ${x}'

	mut c := start_with_files(bin, dir, 20 * time.second, {
		file: served
	}) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	project := snap.projects[0].id
	symbols := c.symbols_at(snap.snapshot, project, file, [x]) or { panic(err) }
	assert symbols[0].name == 'x'
	// The other files, the libraries among them, are still read from disk.
	y := c.symbols_at(snap.snapshot, project, other, ['export const '.len]) or { panic(err) }
	assert y[0].name == 'fromDisk'
	types := c.types_at(snap.snapshot, project, file, [x]) or { panic(err) }
	assert c.type_to_string(snap.snapshot, project, types[0].id) or { panic(err) } == '1'

	// Once the file is no longer served, a new snapshot reads it from disk.
	os.write_file(file, 'const renamed = 2;\nexport {};\n') or { panic(err) }
	c.stop_serving(file)
	changed := c.update_snapshot_changed(snap, [file]) or { panic(err) }
	after := c.symbols_at(changed.snapshot, changed.projects[0].id, file, ['const '.len]) or {
		panic(err)
	}
	assert after[0].name == 'renamed'
}

// The texts with the characters JSON escapes: tsgo gets them whole.
fn test_served_text_with_escapes() {
	bin := os.join_path(@VMODROOT, rel_path)
	if !os.is_file(bin) {
		eprintln('skipped: ${bin} is missing')
		return
	}
	dir := os.join_path(os.temp_dir(), 'veslint-overlay-escapes-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	tsconfig := os.join_path(dir, 'tsconfig.json')
	file := os.join_path(dir, 'a.ts')
	os.write_file(tsconfig, '{"compilerOptions":{"strict":true,"noEmit":true},"include":["*.ts"]}') or {
		panic(err)
	}
	os.write_file(file, '\xFF') or { panic(err) }
	// A NUL, a tab, a quote, a backslash, U+2028, an emoji and a control character before `z`.
	prefix := 'const s = "\\"\\\\\t\x01"; /* \x00 \xE2\x80\xA8 \xF0\x9F\x98\x80 */ '
	served := prefix + 'const z = 3;\nexport {};\n'
	// In UTF-16 units: every character of the prefix is one unit but the emoji (two); U+2028 is
	// three bytes and the emoji four.
	z := prefix.len - 2 - 2 + 'const '.len
	mut c := start_with_files(bin, dir, 20 * time.second, {
		file: served
	}) or { panic(err) }
	defer {
		c.shutdown()
	}
	c.initialize() or { panic(err) }
	snap := c.create_snapshot([tsconfig]) or { panic(err) }
	symbols := c.symbols_at(snap.snapshot, snap.projects[0].id, file, [z]) or { panic(err) }
	assert symbols[0].name == 'z'
}
