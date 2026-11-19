module main

import json2
import os
import time
import treesitter { Ident }
import offsets
import tsgo
import svelte

// ---- main_test.v ----

fn read_app() string {
	raw := os.read_file(os.join_path(@VMODROOT, 'app.ts')) or { panic(err) }
	src, _ := offsets.strip_bom(raw)
	return src
}

fn declared(src string) []Ident {
	p := treesitter.new_parser() or { panic(err) }
	defer {
		p.close()
	}
	tree := p.parse(src) or { panic(err) }
	defer {
		treesitter.tree_delete(tree)
	}
	return p.identifiers(tree, src, false)
}

fn test_unescape_leading_underscores() {
	// tsgo stores `__x` as `___x` (TypeScript's escaping for symbol names).
	assert unescape_leading_underscores('___filename') == '__filename'
	assert unescape_leading_underscores('____three') == '___three'
	assert unescape_leading_underscores('__type') == '__type'
	assert unescape_leading_underscores('_uno') == '_uno'
	assert unescape_leading_underscores('x') == 'x'
}

// With a real tsgo: if byte offsets were sent instead of UTF-16 ones, up to `fiesta` it would
// "work by chance" and the invariant of step 8 must catch it at `x`.
fn test_invariant_detects_bytes_sent_instead_of_utf16() {
	src := read_app()
	idents := declared(src)
	utf16, display := offsets.utf16_positions(src, idents)
	file := os.join_path(@VMODROOT, 'app.ts')
	cfg := os.join_path(@VMODROOT, 'tsconfig.json')
	mut client := tsgo.start(os.join_path(@VMODROOT, tsgo.rel_path), @VMODROOT, 10 * time.second) or {
		panic(err)
	}
	defer {
		client.shutdown()
	}
	_ = client.initialize() or { panic(err) }
	snap := client.create_snapshot([cfg]) or { panic(err) }
	project := snap.projects[0].id
	good := FileWork{
		path:     'app.ts'
		abs_path: file
		tsconfig: cfg
		idents:   idents
		offsets:  utf16
		display:  display
	}
	check_invariant(good, client.symbols_at(snap.snapshot, project, file, utf16) or { panic(err) },
		false) or { panic(err) }
	byte_offsets := idents.map(it.start_byte)
	bad := FileWork{
		...good
		offsets: byte_offsets
	}
	check_invariant(bad, client.symbols_at(snap.snapshot, project, file, byte_offsets) or {
		panic(err)
	}, false) or {
		assert err.msg().contains('`x`')
		return
	}
	assert false, 'the invariant should have caught the mismatch'
}

fn test_tsv_field() {
	assert tsv_field('a\tb\nc\\d\re') == 'a\\tb\\nc\\\\d\\re'
	assert tsv_field('unchanged') == 'unchanged'
}

fn setup_of(text string) !RuleSetup {
	return rule_setup(json2.decode[json2.Any](text)!.as_map(), 'test.json')!
}

fn test_rule_setup_names() {
	// A rule of veslint is named by its full ESLint id. A name without a plugin is a rule of ESLint
	// core (`require-await` and `semi` are not ported), and the rules of other plugins are ignored
	// (when active).
	s := setup_of('{"require-await": [0], "@typescript-eslint/require-await": [2], "no-unsafe-call": "warn", "@typescript-eslint/no-unsafe-call": "warn", "@typescript-eslint/await-thenable": "off", "await-thenable": "error", "semi": 2, "quotes": 0}') or {
		panic(err)
	}
	assert s.rules.map(it.name) == ['@typescript-eslint/require-await',
		'@typescript-eslint/no-unsafe-call']
	assert s.rules.map(it.error) == [true, false]
	assert s.ignored == ['no-unsafe-call', 'await-thenable', 'semi']
	// The name of every ported rule of a plugin without its prefix turns on no rule of veslint; a
	// rule of ESLint core is named without one.
	for name in rules.names {
		if !name.contains('/') {
			u := setup_of('{"${name}": "error"}') or { panic(err) }
			assert u.rules.map(it.name) == [name], name
			assert u.ignored.len == 0, name
			continue
		}
		assert name.starts_with(rules.typescript_eslint_prefix) || name.starts_with('seyfert/')
			|| name.starts_with('unicorn/') || name.starts_with('@stylistic/')
			|| name.starts_with('perfectionist/') || name.starts_with('marcrock/')
			|| name.starts_with('promise/')
			|| name.starts_with('vue/') || name.starts_with('svelte/')
			|| name.starts_with('@eslint-community/eslint-comments/'), name
		short := name.all_after_last('/')
		u := setup_of('{"${short}": "error"}') or { panic(err) }
		// `dot-notation` and `no-implied-eval` are also ported rules of ESLint core.
		if short in rules.names {
			assert u.rules.map(it.name) == [short], name
			continue
		}
		assert u.rules.len == 0, name
		assert u.ignored == [short]
	}
}

fn test_rule_setup_options() {
	// Equivalent to the defaults.
	setup_of('{"@typescript-eslint/no-floating-promises": ["error", {"ignoreVoid": true, "allowForKnownSafeCalls": []}], "@typescript-eslint/return-await": [2, "in-try-catch"], "@typescript-eslint/no-misused-promises": [2, {}]}') or {
		panic(err)
	}
	// Options that are not the defaults.
	setup_of('{"@typescript-eslint/return-await": [2, "always"], "@typescript-eslint/no-floating-promises": ["error", {"ignoreVoid": false, "ignoreIIFE": true, "checkThenables": true}], "@typescript-eslint/no-misused-promises": [2, {"checksVoidReturn": {"arguments": false}}], "@typescript-eslint/no-unsafe-member-access": [2, {"allowOptionalChaining": true}]}') or {
		panic(err)
	}
	// A value the rule does not have, options for a rule without them, or a severity that does not
	// exist.
	for text in ['{"@typescript-eslint/return-await": [2, "sometimes"]}',
		'{"@typescript-eslint/no-for-in-array": [2, {}]}',
		'{"@typescript-eslint/no-misused-promises": [2, {"checksVoidReturn": {"nothing": false}}]}',
		'{"@typescript-eslint/no-floating-promises": "fatal"}',
		'{"@typescript-eslint/no-floating-promises": []}'] {
		if _ := setup_of(text) {
			assert false, text
		}
	}
}

// The value of a rule that ESLint does not take is an error with what the eslint command prints
// for it; the cases come from tools/gen_rule_option_cases.mjs.
fn test_rule_setup_errors_are_those_of_eslint() {
	raw := os.read_file(os.join_path(@VMODROOT, 'tests', 'rule_option_cases.json')) or {
		panic(err)
	}
	data := (json2.decode[json2.Any](raw) or { panic(err) }).as_map()
	id := '@typescript-eslint/no-floating-promises'
	mut checked := 0
	for item in data['values'] or { panic('no values') }.as_array() {
		entry := item.as_map()
		value := entry['value'] or { panic('no value') }
		message := entry['message'] or { panic('no message') }
		expected := if message is string { 'test.json: ${message}' } else { '' }
		mut got := ''
		rule_setup({
			id: value
		}, 'test.json') or { got = err.msg() }
		assert got == expected, value.json_str()
		checked++
	}
	assert checked >= 35
}

// setup_error is the error of a `rules` section; '' when veslint takes it.
fn setup_error(text string) string {
	setup_of(text) or { return err.msg() }
	return ''
}

fn test_rule_setup_order_of_errors() {
	// ESLint checks the value of every rule before the options of any, and the options in the order
	// of the configuration, whatever the order veslint has the rules in.
	assert setup_error('{"@typescript-eslint/await-thenable": [2, 1], "@typescript-eslint/no-floating-promises": "fatal"}').starts_with('test.json: Configuration for rule "@typescript-eslint/no-floating-promises" is invalid. Expected severity')
	assert setup_error('{"@typescript-eslint/await-thenable": [2, 1], "@typescript-eslint/no-floating-promises": [2, 1]}') == 'test.json: Key "rules": Key "@typescript-eslint/await-thenable":\n\tValue 1 should be object.\n'
	// The name of a ported rule without its prefix is a rule of ESLint core: veslint does not
	// validate its options.
	assert setup_error('{"no-floating-promises": ["error", {"nope": 1}]}') == ''
	// A rule veslint does not have is not validated; nor are the options of a rule that is off,
	// until a comment turns it on.
	s := setup_of('{"semi": [2, {"nope": 1}], "@typescript-eslint/no-floating-promises": ["off", {"nope": 1}], "@typescript-eslint/await-thenable": [0, 1, 2], "@typescript-eslint/return-await": ["off", "always"]}') or {
		panic(err)
	}
	assert s.rules.len == 0
	assert s.off_problems == {
		'@typescript-eslint/no-floating-promises': 'Value {"nope":1} should NOT have additional properties.\n\t\tUnexpected property "nope". Expected properties: "allowForKnownSafeCalls", "allowForKnownSafePromises", "checkThenables", "ignoreIIFE", "ignoreVoid".'
		'@typescript-eslint/await-thenable':       'Value [1,2] should NOT have more than 1 items.'
	}
	assert '@typescript-eslint/return-await' in s.base_options
}

// ---- cpus_test.v ----

// The minipc: two cores with two threads each, CPUs n and n + 2 being the threads of a core.
const minipc_cores = {
	0: '0,2'
	1: '1,3'
	2: '0,2'
	3: '1,3'
}

fn test_choose_cpus_takes_the_current_cpu_and_one_of_another_core() {
	all := [0, 1, 2, 3]
	assert choose_cpus(all, 3, minipc_cores, 2) == [3, 0]
	assert choose_cpus(all, 2, minipc_cores, 2) == [2, 3]
	assert choose_cpus(all, 0, minipc_cores, 2) == [0, 1]
	assert choose_cpus(all, 1, minipc_cores, 2) == [1, 2]
	// The other thread of a core comes after a CPU of each core.
	assert choose_cpus(all, 0, minipc_cores, 3) == [0, 1, 2]
	assert choose_cpus(all, 3, minipc_cores, 1) == [3]
}

fn test_choose_cpus_restricts_nothing() {
	all := [0, 1, 2, 3]
	assert choose_cpus(all, 3, minipc_cores, 0) == []
	assert choose_cpus(all, 3, minipc_cores, 4) == []
	assert choose_cpus(all, 3, minipc_cores, 8) == []
	// Already on that many CPUs or fewer (`taskset -c 3`): there is nothing to take away.
	assert choose_cpus([3], 3, minipc_cores, 2) == []
	assert choose_cpus([2, 3], 3, minipc_cores, 2) == []
}

fn test_choose_cpus_among_the_allowed_ones() {
	// Sixteen CPUs whose cores have the threads n and n + 8 (a Ryzen 7), under `taskset -c 4-15`.
	mut cores := map[int]string{}
	for cpu in 0 .. 16 {
		cores[cpu] = '${cpu % 8},${cpu % 8 + 8}'
	}
	allowed := []int{len: 12, init: index + 4}
	assert choose_cpus(allowed, 9, cores, 2) == [9, 10]
	// From the last allowed CPU it goes round to the first.
	assert choose_cpus(allowed, 15, cores, 2) == [15, 4]
	assert choose_cpus(allowed, 15, cores, 3) == [15, 4, 5]
	// A current CPU that is not allowed, or unknown (-1): from the first allowed one.
	assert choose_cpus(allowed, 0, cores, 2) == [4, 5]
	assert choose_cpus(allowed, -1, cores, 2) == [4, 5]
}

fn test_choose_cpus_without_topology() {
	// Without topology every CPU is a core of its own: the current one and the next ones.
	assert choose_cpus([1, 3, 5, 7], 5, map[int]string{}, 2) == [5, 7]
	assert choose_cpus([1, 3, 5, 7], 7, map[int]string{}, 3) == [7, 1, 3]
	// Every allowed CPU in the same core: its threads.
	same_core := {
		0: '0-2'
		1: '0-2'
		2: '0-2'
	}
	assert choose_cpus([0, 1, 2], 1, same_core, 2) == [1, 2]
}

fn test_cpus_from_env() {
	saved := os.getenv_opt('VESLINT_CPUS')
	defer {
		if value := saved {
			os.setenv('VESLINT_CPUS', value, true)
		} else {
			os.unsetenv('VESLINT_CPUS')
		}
	}
	os.unsetenv('VESLINT_CPUS')
	assert cpus_from_env()! == 2
	os.setenv('VESLINT_CPUS', '', true)
	assert cpus_from_env()! == 2
	for raw, want in {
		'0':   0
		'1':   1
		'3':   3
		' 4 ': 4
	} {
		os.setenv('VESLINT_CPUS', raw, true)
		assert cpus_from_env()! == want
	}
	for raw in ['two', '-1', '1.5', '007', '+2'] {
		os.setenv('VESLINT_CPUS', raw, true)
		if value := cpus_from_env() {
			assert false, '`${raw}` gave ${value}'
		} else {
			assert err.msg().contains('VESLINT_CPUS must be a number of CPUs'), err.msg()
		}
	}
}

// ---- server_test.v ----

// RequestQueue (server.v): the requests come out in the order they were read, and the current one
// is given up when a later one lints the same files.
fn test_request_queue_gives_up_superseded_requests() {
	requests := chan ServerRequest{cap: 8}
	mut queue := &RequestQueue{
		requests: requests
	}
	for files in ['a.ts', 'b.ts', '', 'a.ts'] {
		requests <- ServerRequest{
			files: files
		}
	}
	requests.close()
	mut order := []string{}
	mut stops := []bool{}
	for {
		request := queue.next() or { break }
		queue.current = request.files
		order << request.files
		stops << queue.stop()
	}
	assert order == ['a.ts', 'b.ts', '', 'a.ts']
	// a.ts is linted again later; b.ts, a request without files and the last a.ts are not.
	assert stops == [true, false, false, false]
}

// A resolved configuration keeps what a runes function of parserOptions.svelteConfig gave for
// each .svelte file (svelteConfigRunes), also saved (relative paths): the file is parsed with it,
// the other files as their configuration says.
fn test_resolved_svelte_config_runes() {
	base := os.join_path(os.temp_dir(), 'veslint-runes-${os.getpid()}')
	text := '{"configs": [{"rules": {"prefer-const": "error"}, "languageOptions": {"parserOptions": {"svelteConfig": {"compilerOptions": {}}}}}], "files": [{"path": "a.svelte", "config": 0, "svelteConfigRunes": true}, {"path": "b.svelte", "config": 0, "svelteConfigRunes": false}, {"path": "c.svelte", "config": 0}]}'
	files := ['a.svelte', 'b.svelte', 'c.svelte'].map(os.join_path(base, it))
	loaded := loaded_from_resolved(text, 'veslint.json', base, files) or { panic(err) }
	assert loaded.svelte_parse_options(files[0]) == svelte.ParseOptions{
		config: .on
	}
	assert loaded.svelte_parse_options(files[1]) == svelte.ParseOptions{
		config: .off
	}
	assert loaded.svelte_parse_options(files[2]) == svelte.ParseOptions{}
	assert loaded.file_language(files[1], loaded.configs[0].language).svelte_config_runes == 0
	assert loaded.file_language(files[2], loaded.configs[0].language).svelte_config_runes == -1
	assert loaded.resolved.contains('"svelteConfigRunes":true')
}
