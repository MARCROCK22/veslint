module treesitter

// The dialect of each extension, as TypeScript's getScriptKindFromFileName and getLanguageVariant
// decide it: JSX in .tsx, and the comparison ignores case. JavaScript files are told apart to
// reject them.
fn test_dialect_of_each_extension() {
	for path in ['a.js', 'a.jsx', 'a.mjs', 'a.cjs', 'dir.ts/a.JS', '/x/y.Jsx', 'a.test.cjs'] {
		assert is_javascript_path(path), path
		assert !uses_jsx_dialect(path), path
	}
	for path in ['a.tsx', 'A.TSX', 'a.d.tsx'] {
		assert !is_javascript_path(path), path
		assert uses_jsx_dialect(path), path
	}
	for path in ['a.ts', 'a.mts', 'a.cts', 'a.d.ts', 'a.js.ts', 'a', 'a.json', 'js', 'dir.js/a',
		'.jsx/a.ts'] {
		assert !is_javascript_path(path), path
		assert !uses_jsx_dialect(path), path
	}
}
