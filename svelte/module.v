module svelte

import treesitter

// A `.svelte.ts` module (spec §11, parseAsScript): svelte-eslint-parser hands typescript-eslint
// the module with, after its leading white space, the declarations of the runes it references
// (analyzeRuneVariables, as for a component's script: runes are on in a module), so that
// typescript-eslint type-checks `$state(…)` and the others; and the runes are variables of the
// global scope. Its `$derived(…)` transforms only change what is inside the argument's function
// for TypeScript, not the types the rules ask for, and are not made here: the virtual code is the
// file with one piece inserted.

// ModuleVirtual is the virtual code of a `.svelte.ts` module: `inserted` bytes (ASCII, so as many
// UTF-16 units) of declarations at byte offset `at` of the file.
pub struct ModuleVirtual {
pub:
	code     string
	at       int
	inserted int
}

// is_svelte_module_path: the file is a Svelte module (`.svelte.ts`; a `.svelte.js` is JavaScript,
// which veslint does not lint).
pub fn is_svelte_module_path(path string) bool {
	return path.to_lower().ends_with('.svelte.ts')
}

// module_virtual is the virtual code of a `.svelte.ts` module: the runes it references without
// declaring them (an identifier of a rune's name that is not a name the module declares at its top
// level), in svelte-eslint-parser's order.
pub fn (p &Parsers) module_virtual(src string) !ModuleVirtual {
	tree := parse_ts(p.ts, src)!.rows
	defer {
		treesitter.rows_free(tree)
	}
	root := treesitter.root_node(tree)
	mut referenced := map[string]bool{}
	mut declared := map[string]bool{}
	mut stack := [root]
	for stack.len > 0 {
		n := stack.pop()
		kind := treesitter.node_kind(n)
		if kind in ['identifier', 'shorthand_property_identifier'] {
			name := src[treesitter.node_start(n)..treesitter.node_end(n)]
			if name in rune_globals {
				parent := treesitter.node_parent(n) or { root }
				pk := treesitter.node_kind(parent)
				if pk in ['variable_declarator', 'function_declaration', 'class_declaration',
					'import_specifier', 'namespace_import', 'import_clause']
					&& node_is_name_of(parent, n) {
					declared[name] = true
				} else {
					referenced[name] = true
				}
			}
		}
		kids := treesitter.named_children(n)
		for i := kids.len - 1; i >= 0; i-- {
			stack << kids[i]
		}
	}
	mut inserted := ''
	for g in rune_globals {
		if referenced[g] && !declared[g] {
			inserted += rune_declarations(g)
		}
	}
	at := js_leading_space_len(src)
	return ModuleVirtual{
		code:     src[..at] + inserted + src[at..]
		at:       at
		inserted: inserted.len
	}
}

// node_is_name_of: `n` is the `name` of its declaration `parent` (or the import's binding).
fn node_is_name_of(parent C.vt_node, n C.vt_node) bool {
	if name := treesitter.node_field(parent, 'name') {
		return treesitter.node_start(name) == treesitter.node_start(n)
	}
	return treesitter.node_kind(parent) in ['import_clause', 'namespace_import']
}

// js_leading_space_len is the length of `/^\s*/u.exec(code)[0]` in bytes.
fn js_leading_space_len(s string) int {
	mut i := 0
	for i < s.len {
		if s[i] in [` `, `\t`, `\n`, `\r`, `\v`, `\f`] {
			i++
			continue
		}
		// U+00A0, U+FEFF, U+2028, U+2029 and the other Unicode spaces.
		r := s[i..].runes()
		if r.len > 0 && is_js_space_rune(r[0]) {
			i += r[0].length_in_bytes()
			continue
		}
		break
	}
	return i
}

fn is_js_space_rune(r rune) bool {
	return r in [rune(0xa0), 0xfeff, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000]
		|| (r >= 0x2000 && r <= 0x200a)
}
