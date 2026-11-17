module vue

// ScriptInfo is what the parser knows of the <script> side of the file (see parse_script).
pub struct ScriptInfo {
pub mut:
	program_start int
	program_end   int
	tokens        []Token
	comments      []Token
	// codes are the codes handed to the script parser for the scripts (the setup pre-pass and
	// the final code).
	codes []string
}

// script_lang is getParserLangFromSFC: the lang of the <script setup> when there are exactly two
// scripts and one is setup, else of the first script; none without a script or a lang.
pub fn (d &Document) script_lang() ?string {
	scripts := d.top_elements('script')
	mut script := -1
	if scripts.len == 2 {
		for s in scripts {
			if d.is_script_setup(s) {
				script = s
				break
			}
		}
	}
	if script < 0 && scripts.len > 0 {
		script = scripts[0]
	}
	if script < 0 {
		return none
	}
	return d.lang_of(script)
}

fn (mut c ExprContext) parse_script() {
}
