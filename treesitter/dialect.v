module treesitter

// Which dialect of the grammar reads a file, by its extension, as TypeScript decides the kind of
// script and its language variant (getScriptKindFromFileName and getLanguageVariant of its
// parser): the comparison ignores case, and a file without a known extension is TypeScript.

// javascript_extensions are the extensions of ScriptKind.JS and ScriptKind.JSX.
const javascript_extensions = ['.js', '.jsx', '.mjs', '.cjs']

// path_extension is the text from the last `.` of the file name, in lower case; '' without one.
fn path_extension(path string) string {
	name := path.all_after_last('/')
	dot := name.last_index('.') or { return '' }
	return name[dot..].to_lower()
}

// is_javascript_path: TypeScript reads the file as JavaScript (.js, .jsx, .mjs, .cjs), where types
// come from JSDoc. veslint does not lint those files.
pub fn is_javascript_path(path string) bool {
	return path_extension(path) in javascript_extensions
}

// uses_jsx_dialect: the file is read with LanguageVariant.JSX, that is, with JSX and without
// `<T>x` assertions: a .tsx.
pub fn uses_jsx_dialect(path string) bool {
	return path_extension(path) == '.tsx'
}
