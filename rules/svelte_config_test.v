module rules

import json2
import svelte

// The static reading of svelte.config.js (svelte_config.v): the cases of svelte-eslint-parser's
// tests/src/svelte-config/parser.ts, and more whose results its parseConfig 1.10.1 gave.

struct SvcfgCase {
	code   string
	runes  int = -1
	routes string
}

const svcfg_cases = [
	SvcfgCase{
		code:  'export default {compilerOptions:{runes:true}}'
		runes: 1
	},
	SvcfgCase{
		code:  'const opt = {compilerOptions:{runes:true}}\nexport default opt'
		runes: 1
	},
	SvcfgCase{
		code:  'const compilerOptions = {runes:true}\nexport default {compilerOptions}'
		runes: 1
	},
	SvcfgCase{
		code:   'const kit = {files:{routes:"src/custom"}}\nconst compilerOptions = {runes:false}\nexport default {compilerOptions,kit}'
		runes:  0
		routes: 'src/custom'
	},
	SvcfgCase{
		code:  'const opt = {compilerOptions:{runes:true}}\nexport default {...opt}'
		runes: 1
	},
	SvcfgCase{
		code:  'const key = "compilerOptions"\nexport default {[key]:{runes:false}}'
		runes: 0
	},
	SvcfgCase{
		code:  'const {compilerOptions} = {compilerOptions:{runes:true}}\nexport default {compilerOptions}'
		runes: 1
	},
	SvcfgCase{
		code:  'const {compilerOptions = {runes:true}} = {}\nexport default {compilerOptions}'
		runes: 1
	},
	SvcfgCase{
		code: 'export default {compilerOptions:{}}'
	},
	// The cache of an object makes a repeated key keep its first value in a static object.
	SvcfgCase{
		code:   "export default {kit:{files:{routes:'a', routes:'b'}}}"
		routes: 'a'
	},
	SvcfgCase{
		code: "export default {kit:{files:{routes:'a', hooks: () => 1}}}"
	},
	SvcfgCase{
		code: 'export default {compilerOptions:{runes: undefined}}'
	},
	SvcfgCase{
		code: 'export default {compilerOptions:{runes: missing}}'
	},
	SvcfgCase{
		code: 'var a = {runes:true}; var a = {runes:false}; export default {compilerOptions: a}'
	},
	SvcfgCase{
		code:  "export default {compilerOptions:{runes: 'yes'}, kit: {files: {routes: 1}}}"
		runes: 1
	},
	SvcfgCase{
		code:  'export default {...{compilerOptions:{runes:true}}, compilerOptions: {runes: false}}'
		runes: 0
	},
	SvcfgCase{
		code:  'export default {compilerOptions: {runes: true}, ...unknownThing}'
		runes: 1
	},
	SvcfgCase{
		code: 'const [a, {b = {runes: true}}] = [1, {}]; export default {compilerOptions: b}'
	},
	SvcfgCase{
		code: 'export default defineConfig({compilerOptions:{runes:true}})'
	},
	SvcfgCase{
		code: "const x = {files: {routes: 'r'}}; export default {kit: {...x, files: {...x.files}}}"
	},
	SvcfgCase{
		code:   "const x = {files: {routes: 'r'}}; export default {kit: {...x}}"
		routes: 'r'
	},
	SvcfgCase{
		code:  'export default {compilerOptions: {runes: {}}}'
		runes: 1
	},
	SvcfgCase{
		code:  'export default {compilerOptions: {runes: 0n}}'
		runes: 0
	},
	SvcfgCase{
		code: 'export default {compilerOptions: {runes: null}}'
	},
]

fn test_svelte_config_static_reading() {
	for case in svcfg_cases {
		got := svcfg_parse(case.code)
		assert got.runes == case.runes, case.code
		assert got.routes == case.routes, case.code
	}
}

// svelte_parse_options: svelteFeatures.runes (even neither true nor false) wins; a given
// svelteConfig replaces svelte.config.js (whose path is looked for from the file: there is none
// above this directory's files).
fn test_svelte_parse_options() {
	path := @FILE
	for text, want in {
		'{}':                                                                                                            svelte.ParseOptions{}
		'{"parserOptions": {"svelteFeatures": {"runes": false}}}':                                                       svelte.ParseOptions{
			features_set: true
			features:     .off
		}
		'{"parserOptions": {"svelteFeatures": {"runes": true}, "svelteConfig": {"compilerOptions": {"runes": false}}}}': svelte.ParseOptions{
			features_set: true
			features:     .on
		}
		'{"parserOptions": {"svelteFeatures": {"runes": 1}}}':                                                           svelte.ParseOptions{
			features_set: true
		}
		'{"parserOptions": {"svelteFeatures": {"runes": null}}}':                                                        svelte.ParseOptions{}
		'{"parserOptions": {"svelteConfig": {"compilerOptions": {"runes": true}}}}':                                     svelte.ParseOptions{
			config: .on
		}
		'{"parserOptions": {"svelteConfig": {"compilerOptions": {"runes": "yes"}}}}':                                    svelte.ParseOptions{}
		'{"parserOptions": {"svelteConfig": {"kit": {}}}}':                                                              svelte.ParseOptions{}
	} {
		language := parse_language_options(json2.decode[json2.Any](text) or { panic(err) })
		assert svelte_parse_options(language, path) == want, text
	}
}
