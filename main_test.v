module main

import json2
import os
import time
import treesitter { Ident }
import offsets
import tsgo

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
		assert name.starts_with(rules.typescript_eslint_prefix) || name.starts_with('seyfert/'), name
		short := name.all_after_last('/')
		u := setup_of('{"${short}": "error"}') or { panic(err) }
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
		'{"@typescript-eslint/await-thenable": [2, {}]}',
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
	assert setup_error('{"@typescript-eslint/await-thenable": [2, 1], "@typescript-eslint/no-floating-promises": [2, 1]}') == 'test.json: Key "rules": Key "@typescript-eslint/await-thenable":\n\tValue [1] should NOT have more than 0 items.\n'
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
		'@typescript-eslint/await-thenable':       'Value [1,2] should NOT have more than 0 items.'
	}
	assert '@typescript-eslint/return-await' in s.base_options
}
