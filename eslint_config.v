module main

import json2
import os
import rules

// An ESLint configuration file (`eslint.config.js`, `.mjs`, `.cjs`, `.ts`…) is JavaScript, so
// ESLint itself resolves it: veslint runs `bun` once, in the directory of the configuration, with
// a script that asks the project's own ESLint which configuration applies to each file
// (`files`, `ignores`, the rules and options, `linterOptions`, and of `languageOptions` what
// decides the scopes of a file: the ecmaVersion, the sourceType, the globals and the parser
// options typescript-eslint's scope manager reads, and how the parser gets the types) and prints
// it as JSON. That JSON is also what
// `--print-config` prints, and `--config` accepts it back, so a saved copy needs no JavaScript
// runtime.

// eslint_resolver is the script: its arguments are the directory veslint runs in (ESLint's `cwd`:
// with `--config`, the patterns of the configuration are relative to it, as in `eslint -c`), the
// configuration file, a JSON file with the files to lint (absolute paths) and the mode: `lookup`
// when no `--config` was given (a directory to lint), where ESLint finds the configuration of each
// file as the eslint command does (the closest eslint.config.* from the file's directory up), and
// the given file is only where `eslint` and typescript-eslint are resolved from. A configuration
// ESLint does not take gives `error`: what the eslint command prints for it (getErrorMessage of
// bin/eslint.js), which is the text of the message template of the error or, without one, its
// message (the command prints the stack too).
const eslint_resolver = "
import { ESLint } from 'eslint';
import { builtinRules } from 'eslint/use-at-your-own-risk';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const [, cwd, configPath, listPath, mode, inputsPath] = process.argv;
const { files } = JSON.parse(fs.readFileSync(listPath, 'utf8'));
// With `inputsPath`, what the resolution read is written there for the cache of resolved
// configurations (config_cache.v): the files read through fs, the modules loaded (in bun,
// require.cache has the ES modules too) and the environment variables read, with their values.
const reads = new Set();
const envRead = {};
if (inputsPath) {
  const track = file => {
    try {
      const name = file instanceof URL ? fileURLToPath(file) : Buffer.isBuffer(file) ? file.toString() : file;
      if (typeof name === 'string') reads.add(path.resolve(name));
    } catch {}
  };
  for (const name of ['readFileSync', 'readFile']) {
    const original = fs[name];
    fs[name] = function (file, ...rest) {
      track(file);
      return original.call(this, file, ...rest);
    };
  }
  const readPromise = fs.promises.readFile;
  fs.promises.readFile = function (file, ...rest) {
    track(file);
    return readPromise.call(this, file, ...rest);
  };
  const note = (target, key) => {
    if (typeof key === 'string' && !Object.hasOwn(envRead, key)) envRead[key] = target[key] ?? null;
  };
  process.env = new Proxy(process.env, {
    get(target, key) {
      note(target, key);
      return target[key];
    },
    has(target, key) {
      note(target, key);
      return key in target;
    },
  });
}
// The typescript-estree that typescript-eslint uses in this project: its resolveProjectList and
// the tsconfigRootDir it infers from where its configs were read.
let estree;
const loadEstree = () => {
  if (estree !== undefined) return estree;
  estree = null;
  try {
    const fromConfig = createRequire(path.resolve(configPath));
    let base = fromConfig;
    try {
      base = createRequire(fromConfig.resolve('typescript-eslint'));
    } catch {}
    const dir = path.dirname(base.resolve('@typescript-eslint/typescript-estree/package.json'));
    estree = {
      resolveProjectList: base(path.join(dir, 'dist', 'parseSettings', 'resolveProjectList.js')).resolveProjectList,
      getInferredTSConfigRootDir: base(path.join(dir, 'dist', 'parseSettings', 'candidateTSConfigRootDirs.js')).getInferredTSConfigRootDir,
    };
  } catch {}
  return estree;
};
// The tsconfig files `parserOptions.project` names, as typescript-estree resolves them (in their
// order, with the globs expanded, relative to tsconfigRootDir: the given one, the one inferred, or
// ESLint's cwd), as absolute paths; `true` (the closest tsconfig.json of each file) when it names
// none.
const projectList = given => {
  const list = (Array.isArray(given.project) ? given.project : [given.project]).filter(p => typeof p === 'string');
  if (list.length === 0) return true;
  const resolver = loadEstree();
  let root = cwd;
  if (typeof given.tsconfigRootDir === 'string') {
    root = path.resolve(given.tsconfigRootDir);
  } else {
    try {
      root = resolver?.getInferredTSConfigRootDir?.() ?? cwd;
    } catch {}
  }
  let paths = [...new Set(list.map(p => path.resolve(root, p)))];
  if (resolver?.resolveProjectList) {
    try {
      paths = [...resolver.resolveProjectList({ project: list, projectFolderIgnoreList: given.projectFolderIgnoreList, tsconfigRootDir: root, singleRun: true }).values()];
    } catch {}
  }
  return paths.length > 0 ? paths : true;
};
try {
const eslint = new ESLint(mode === 'lookup' ? { cwd } : { cwd, overrideConfigFile: configPath });
const configs = [];
const indexes = new Map();
const pluginRules = new Set();
const ruleDefaults = {};
const out = [];
for (const file of files) {
  const config = (await eslint.isPathIgnored(file)) ? undefined : await eslint.calculateConfigForFile(file);
  if (!config) {
    // ESLint's own message for a file it does not lint.
    const [result] = await eslint.lintText('', { filePath: file, warnIgnored: true });
    out.push({ path: file, message: result?.messages[0]?.message ?? 'File ignored.' });
    continue;
  }
  for (const [namespace, plugin] of Object.entries(config.plugins ?? {})) {
    if (namespace === '@' || namespace === '@typescript-eslint') continue;
    for (const name of Object.keys(plugin?.rules ?? {})) pluginRules.add(namespace + '/' + name);
  }
  // With reportUnusedInlineConfigs, ESLint compares the options of a configuration comment, on
  // top of the default options of the rule, with the configured ones.
  const unusedInline = config.linterOptions?.reportUnusedInlineConfigs;
  if (unusedInline && unusedInline !== 'off') {
    const withDefaults = (id, rule) => {
      const defaults = rule?.meta?.defaultOptions;
      if (Array.isArray(defaults) && defaults.length > 0) ruleDefaults[id] = defaults;
    };
    for (const [name, rule] of builtinRules) withDefaults(name, rule);
    for (const [namespace, plugin] of Object.entries(config.plugins ?? {})) {
      if (namespace === '@') continue;
      for (const [name, rule] of Object.entries(plugin?.rules ?? {})) withDefaults(namespace + '/' + name, rule);
    }
  }
  // How typescript-eslint gets the types (createParseSettings of typescript-estree): the project
  // service, or the programs of `project` (or the ones given in `programs`); and, of the other
  // parser options, the ones typescript-eslint's parser gives its scope manager, and
  // isolatedDeclarations, which a rule reads.
  const given = config.languageOptions?.parserOptions ?? {};
  const service = given.projectService || (given.project && given.projectService !== false && process.env.TYPESCRIPT_ESLINT_PROJECT_SERVICE === 'true');
  const parserOptions = service ? { projectService: true } : given.project ? { project: projectList(given) } : given.programs ? { project: true } : {};
  if (service) {
    // What decides whether a single run takes a file from a Program made for its tsconfig
    // instead of the project service (useSingleRunProgramForProjectService of typescript-estree).
    let root = cwd;
    if (typeof given.tsconfigRootDir === 'string') {
      root = path.resolve(given.tsconfigRootDir);
    } else {
      try {
        root = loadEstree()?.getInferredTSConfigRootDir?.() ?? cwd;
      } catch {}
    }
    parserOptions.tsconfigRootDir = root;
    const allowDefaultProject = typeof given.projectService === 'object' ? given.projectService?.allowDefaultProject : undefined;
    if (allowDefaultProject?.length) parserOptions.projectService = { allowDefaultProject };
    if (given.extraFileExtensions?.length) parserOptions.extraFileExtensions = given.extraFileExtensions;
    if (given.programs != null) parserOptions.programs = true;
    if (given.disallowAutomaticSingleRunInference) parserOptions.disallowAutomaticSingleRunInference = true;
  }
  for (const name of ['sourceType', 'lib', 'jsxPragma', 'jsxFragmentName', 'isolatedDeclarations']) {
    if (given[name] !== undefined) parserOptions[name] = given[name];
  }
  for (const name of ['globalReturn', 'jsx']) {
    if (given.ecmaFeatures?.[name] !== undefined) (parserOptions.ecmaFeatures ??= {})[name] = given.ecmaFeatures[name];
  }
  // What vue-eslint-parser (vueFeatures) and svelte-eslint-parser (svelteFeatures, svelteConfig)
  // parse with, as JSON writes it: a function in it is left out (a function in their place is an
  // empty object, which is what they read of it).
  for (const name of ['vueFeatures', 'svelteFeatures', 'svelteConfig']) {
    if (given[name] === undefined) continue;
    try {
      parserOptions[name] = JSON.parse(JSON.stringify(given[name]) ?? '{}');
    } catch {}
  }
  const languageOptions = {
    ecmaVersion: config.languageOptions?.ecmaVersion,
    sourceType: config.languageOptions?.sourceType,
    globals: config.languageOptions?.globals ?? {},
    parserOptions,
  };
  const slim = { rules: config.rules ?? {}, linterOptions: config.linterOptions ?? {}, languageOptions };
  // The shared settings, which rules read (context.settings: eslint-plugin-perfectionist's
  // `perfectionist`), when there are any; what JSON cannot write (a function) is left out.
  if (config.settings && Object.keys(config.settings).length > 0) {
    try {
      slim.settings = JSON.parse(JSON.stringify(config.settings));
    } catch {
      slim.settings = {};
      for (const [name, value] of Object.entries(config.settings)) {
        try {
          slim.settings[name] = JSON.parse(JSON.stringify(value) ?? 'null');
        } catch {}
      }
    }
  }
  const key = JSON.stringify(slim);
  if (!indexes.has(key)) {
    indexes.set(key, configs.length);
    configs.push(slim);
  }
  out.push({ path: file, config: indexes.get(key) });
}
const result = { eslint: ESLint.version, pluginRules: [...pluginRules].sort(), configs, files: out };
if (Object.keys(ruleDefaults).length > 0) {
  result.ruleDefaults = Object.fromEntries(Object.entries(ruleDefaults).sort(([a], [b]) => (a < b ? -1 : 1)));
}
// Infinity (an option of @stylistic's experimental rules) as the largest finite number, not null.
process.stdout.write(JSON.stringify(result, (key, value) => (value === Infinity ? Number.MAX_VALUE : value === -Infinity ? -Number.MAX_VALUE : value)));
if (inputsPath) {
  const modules = Object.keys(require.cache).map(key => key.split('?')[0]).filter(key => path.isAbsolute(key));
  fs.writeFileSync(inputsPath, JSON.stringify({ files: [...new Set([...modules, ...reads])], env: envRead }));
}
} catch (error) {
  // An error of ESLint about the configuration has a message template, or names the key that is
  // wrong; any other error is not for veslint to word.
  let message = error instanceof Error ? error.message : '';
  if (typeof error?.messageTemplate === 'string') {
    try {
      const require = createRequire(path.join(process.cwd(), 'veslint.js'));
      const messages = path.join(path.dirname(require.resolve('eslint/package.json')), 'messages');
      message = require(path.join(messages, error.messageTemplate + '.js'))(error.messageData || {});
    } catch {}
  } else if (!message.startsWith('Key ')) {
    throw error;
  }
  process.stdout.write(JSON.stringify({ error: message }));
}
"

const eslint_config_extensions = ['.js', '.mjs', '.cjs', '.ts', '.mts', '.cts']

// ConfigEntry is one of the configurations of a run: the rules veslint applies to the files it is
// for, ESLint's linterOptions and, of its languageOptions, what decides the scopes of a file.
struct ConfigEntry {
	setup         RuleSetup
	report_unused int = 1 // reportUnusedDisableDirectives: 0 off, 1 warn, 2 error
	// reportUnusedInlineConfigs (0 off, 1 warn, 2 error) and the `rules` section as it is: what
	// a configuration comment is compared with.
	report_unused_inline int
	all_rules            map[string]json2.Any
	no_inline_config     bool
	language             rules.LanguageOptions
	plugins              []string // the namespaces of its plugins, when the configuration lists them
	// The parser gets the types from the programs of `parserOptions.project`, not from the project
	// service: the current directory of such a program is the one ESLint runs in.
	project_programs bool
	// The parser gets the types from the project service, which in a single run leaves a file to a
	// Program made for its tsconfig (service_program_root is then the tsconfigRootDir, where the
	// search for that tsconfig stops); empty when it never does (see single_run_program_root).
	service_program_root string
	// The tsconfig files `parserOptions.project` names (absolute paths), of which a file takes the
	// first one that has it; empty for the closest tsconfig of each file.
	projects []string
	// The shared settings of the configuration (`settings`), which rules read.
	settings map[string]json2.Any
}

// language_options reads the `languageOptions` of a configuration.
fn language_options(config map[string]json2.Any) rules.LanguageOptions {
	return rules.parse_language_options(config['languageOptions'] or {
		json2.Any(map[string]json2.Any{})
	})
}

// uses_project_programs reads, from the `languageOptions` of a configuration, how typescript-eslint
// gets the types (createParseSettings of typescript-estree): from the project service when
// `parserOptions.projectService` is set, and otherwise from the programs of `project` (or the ones
// of `programs`), which is what this tells.
fn uses_project_programs(config map[string]json2.Any) bool {
	language := config['languageOptions'] or { return false }
	if language !is map[string]json2.Any {
		return false
	}
	parser := language.as_map()['parserOptions'] or { return false }
	if parser !is map[string]json2.Any {
		return false
	}
	options := parser.as_map()
	if js_truthy(options['projectService'] or { json2.Any(false) }) {
		return false
	}
	return js_truthy(options['project'] or { json2.Any(false) }) || 'programs' in options
}

// single_run_program_root ports the options part of when typescript-estree takes a file of the
// project service from a Program made for its tsconfig in a single run
// (useSingleRunProgramForProjectService and inferSingleRun of typescript-estree 8.72.2): with
// the project service, no `allowDefaultProject`, no `extraFileExtensions` and no `programs`,
// unless `TSESTREE_SINGLE_RUN` is "false", or `disallowAutomaticSingleRunInference`
// without `TSESTREE_SINGLE_RUN` "true" (is_single_run decides the rest). It gives the
// tsconfigRootDir (the resolver adds it to the parser options, and a saved resolved JSON has it
// relative to `base`, its directory; the current directory without it), or '' when the project
// service is used.
fn single_run_program_root(config map[string]json2.Any, base string) string {
	mut options := map[string]json2.Any{}
	if language := config['languageOptions'] {
		if language is map[string]json2.Any {
			if parser := language.as_map()['parserOptions'] {
				if parser is map[string]json2.Any {
					options = parser.as_map().clone()
				}
			}
		}
	}
	// Without `projectService` veslint still gets the types as the project service does (only
	// `project` makes it use the programs of the tsconfig files: project_programs).
	if service := options['projectService'] {
		if service is map[string]json2.Any {
			if listed := service.as_map()['allowDefaultProject'] {
				if listed is []json2.Any && listed.len > 0 {
					return ''
				}
			}
		}
	}
	if extensions := options['extraFileExtensions'] {
		if extensions is []json2.Any && extensions.len > 0 {
			return ''
		}
	}
	if programs := options['programs'] {
		if programs !is json2.Null {
			return ''
		}
	}
	env := os.getenv('TSESTREE_SINGLE_RUN')
	if env == 'false' || (env != 'true'
		&& js_truthy(options['disallowAutomaticSingleRunInference'] or { json2.Any(false) })) {
		return ''
	}
	if root := options['tsconfigRootDir'] {
		if root is string {
			return if os.is_abs_path(root) { root } else { os.abs_path(os.join_path(base, root)) }
		}
	}
	return os.getwd()
}

// is_single_run ports the rest of inferSingleRun: not with `TSESTREE_SINGLE_RUN` "false" (as
// RuleTester lints, which tests/upstream_check.py emulates), and then `TSESTREE_SINGLE_RUN` "true",
// or the eslint command (which veslint stands for) without --fix.
fn is_single_run(fix bool) bool {
	setting := os.getenv('TSESTREE_SINGLE_RUN')
	if setting == 'false' {
		return false
	}
	return setting == 'true' || !fix
}

// single_run_tsconfig ports the rest of useSingleRunProgramForProjectService: the tsconfig.json or
// jsconfig.json closest to the file (getProjectConfigFiles, which looks up to `root`, the
// tsconfigRootDir), when it has no project references (the raw file: they are not inherited
// through `extends`); '' when the project service lints the file.
fn single_run_tsconfig(file string, root string) string {
	mut directory := os.dir(file)
	for {
		for name in ['tsconfig.json', 'jsconfig.json'] {
			candidate := os.join_path(directory, name)
			if os.exists(candidate) {
				if tsconfig_has_references(candidate) {
					return ''
				}
				return candidate
			}
		}
		parent := os.dir(directory)
		if parent.len <= 1 || parent == directory || parent.len < root.len {
			return ''
		}
		directory = parent
	}
	return ''
}

// tsconfig_has_references: the `references` of a tsconfig (JSON with comments and trailing
// commas, as ts.readConfigFile reads it) are not empty.
fn tsconfig_has_references(path string) bool {
	text := os.read_file(path) or { return false }
	parsed := json2.decode[json2.Any](strip_jsonc(text)) or { return false }
	if parsed is map[string]json2.Any {
		if references := parsed.as_map()['references'] {
			return references is []json2.Any && references.len > 0
		}
	}
	return false
}

// strip_jsonc removes the comments and the trailing commas of JSON with comments.
fn strip_jsonc(text string) string {
	mut out := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		c := text[i]
		if c == `"` {
			start := i
			i++
			for i < text.len && text[i] != `"` {
				if text[i] == `\\` {
					i++
				}
				i++
			}
			i++
			out << text[start..if i > text.len { text.len } else { i }].bytes()
			continue
		}
		if c == `/` && i + 1 < text.len && text[i + 1] == `/` {
			for i < text.len && text[i] != `\n` {
				i++
			}
			continue
		}
		if c == `/` && i + 1 < text.len && text[i + 1] == `*` {
			i += 2
			for i + 1 < text.len && !(text[i] == `*` && text[i + 1] == `/`) {
				i++
			}
			i += 2
			continue
		}
		if c == `,` {
			mut j := i + 1
			for j < text.len && text[j] in [` `, `\t`, `\n`, `\r`] {
				j++
			}
			if j < text.len && text[j] in [`}`, `]`] {
				i++
				continue
			}
		}
		out << c
		i++
	}
	return out.bytestr()
}

// named_projects_of reads the tsconfig files `parserOptions.project` names in a configuration: a
// path or a list of them, relative to `base` when they are not absolute; none for `true` (the
// closest tsconfig.json of each file) and for a pattern with globs, which only the resolved form
// has expanded.
fn named_projects_of(config map[string]json2.Any, base string) []string {
	language := config['languageOptions'] or { return []string{} }
	if language !is map[string]json2.Any {
		return []string{}
	}
	parser := language.as_map()['parserOptions'] or { return []string{} }
	if parser !is map[string]json2.Any {
		return []string{}
	}
	project := parser.as_map()['project'] or { return []string{} }
	items := match project {
		[]json2.Any { project }
		string { [json2.Any(project)] }
		else { []json2.Any{} }
	}
	mut out := []string{}
	for item in items {
		if item !is string {
			continue
		}
		path := item.str()
		if path.contains_any('*?[]{}!') {
			return []string{}
		}
		abs := if os.is_abs_path(path) { path } else { os.abs_path(os.join_path(base, path)) }
		if abs !in out {
			out << abs
		}
	}
	return out
}

// config_settings reads the `settings` of a configuration: an object, or none.
fn config_settings(config map[string]json2.Any) map[string]json2.Any {
	settings := config['settings'] or { return map[string]json2.Any{} }
	if settings is map[string]json2.Any {
		return settings.as_map()
	}
	return map[string]json2.Any{}
}

// js_truthy: the value counts as true in JavaScript.
fn js_truthy(value json2.Any) bool {
	if value is json2.Null {
		return false
	}
	return value.json_str() !in ['false', '0', '""']
}

// LoadedConfig is what `--config` gives: the configurations, the one of each file (by absolute
// path), the files ESLint does not lint with its message for them, and the rules of the other
// plugins when ESLint resolved the configuration.
struct LoadedConfig {
	configs        []ConfigEntry
	file_config    map[string]int
	file_notes     map[string]string
	plugin_rules   []string
	strict_plugins bool
	// The default options (meta.defaultOptions) of the rules that have them, when ESLint
	// resolved the configuration and some part of it has reportUnusedInlineConfigs.
	rule_defaults map[string]json2.Any
	resolved      string // the resolved JSON, for --print-config
	only_rule     string // the rule of --rule, the only one that runs
}

// named_projects are the tsconfig files `parserOptions.project` names in the configuration of a
// file (absolute path); empty for the closest tsconfig.
fn (l &LoadedConfig) named_projects(abs_path string) []string {
	index := l.file_config[abs_path] or { return []string{} }
	return l.configs[index].projects
}

// tsconfig_root_dir is the `parserOptions.tsconfigRootDir` of a configuration, or the current
// directory (typescript-estree's default without one it can infer).
fn tsconfig_root_dir(config map[string]json2.Any) string {
	language := config['languageOptions'] or { return os.getwd() }
	if language is map[string]json2.Any {
		if parser := language.as_map()['parserOptions'] {
			if parser is map[string]json2.Any {
				if root := parser.as_map()['tsconfigRootDir'] {
					if root is string {
						return root
					}
				}
			}
		}
	}
	return os.getwd()
}

fn (l &LoadedConfig) lint_config(index int) rules.LintConfig {
	entry := l.configs[index]
	return rules.LintConfig{
		rules:                entry.setup.rules.map(rules.RuleSetting{
			name:     it.name
			severity: if it.error { 2 } else { 1 }
			options:  it.options
		})
		base_options:         entry.setup.base_options
		off_problems:         entry.setup.off_problems
		other_active:         entry.setup.ignored
		only_rule:            l.only_rule
		plugin_rules:         l.plugin_rules
		strict_plugins:       l.strict_plugins
		plugins:              entry.plugins
		report_unused:        entry.report_unused
		report_unused_inline: entry.report_unused_inline
		all_rules:            entry.all_rules
		rule_defaults:        l.rule_defaults
		no_inline_config:     entry.no_inline_config
		language:             entry.language
		settings:             entry.settings
		program_directory:    if entry.project_programs { os.getwd() } else { '' }
		project_programs:     entry.project_programs
	}
}

// load_config_for loads `--config path` for the files of the run: an ESLint configuration file
// (resolved with bun), a resolved JSON, or a JSON with a `rules` section, which is for every file
// (and may have `linterOptions` and `languageOptions` sections, as the output of
// `eslint --print-config` does).
fn load_config_for(path string, files []string) !LoadedConfig {
	return load_config_with(path, files, false)
}

// load_config_with is load_config_for; with `lookup`, `path` is an ESLint configuration file that
// was found, not given, and ESLint finds the configuration of each file itself (see
// eslint_resolver).
fn load_config_with(path string, files []string, lookup bool) !LoadedConfig {
	if os.file_ext(path) in eslint_config_extensions {
		if !os.is_file(path) {
			return error('cannot read ${path}')
		}
		resolved := resolve_cached(os.abs_path(path), files.map(os.abs_path(it)), lookup)!
		return loaded_from_resolved(resolved, path, os.dir(os.abs_path(path)), files)!
	}
	text := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	root := json2.decode[json2.Any](text) or {
		return error('${path}: not valid JSON (${err.msg()})')
	}
	if root is map[string]json2.Any && 'configs' in root && 'files' in root {
		return loaded_from_resolved(text, path, os.dir(os.abs_path(path)), files)!
	}
	setup := load_config(path)!
	mut file_config := map[string]int{}
	for file in files {
		file_config[os.abs_path(file)] = 0
	}
	linter := (root.as_map()['linterOptions'] or { json2.Any(map[string]json2.Any{}) }).as_map()
	// No ESLint reads such a file: its sections count as those of a configuration object do in
	// ESLint, whose `--print-config` prints them normalized. The value of each rule is normalized
	// the same way (a number for the severity, and the options over the default ones of the rule,
	// which veslint has for the rules of ESLint and of typescript-eslint): what a configuration
	// comment is compared with.
	section := (root.as_map()['rules'] or { json2.Any(map[string]json2.Any{}) }).as_map()
	mut all_rules := map[string]json2.Any{}
	for key, value in section {
		id, normalized := rules.normalized_rule_config(key, value)
		// A ported rule under its bare name, unless it is there with the prefix too.
		if id == key || id !in section {
			all_rules[id] = normalized
		}
	}
	// The output of `eslint --print-config` lists the plugins of the configuration, each as its
	// namespace, or as `namespace:name@version`.
	mut plugins := []string{}
	if listed := root.as_map()['plugins'] {
		if listed is []json2.Any {
			plugins = listed.map(it.str().all_before(':'))
		}
	}
	return LoadedConfig{
		configs:     [
			ConfigEntry{
				setup:                setup
				language:             language_options(root.as_map())
				plugins:              plugins
				project_programs:     uses_project_programs(root.as_map())
				service_program_root: single_run_program_root(root.as_map(), os.getwd())
				projects:             named_projects_of(root.as_map(), tsconfig_root_dir(root.as_map()))
				report_unused:        linter_severity(linter['reportUnusedDisableDirectives'] or {
					json2.Any(i64(1))
				})
				no_inline_config:     (linter['noInlineConfig'] or { json2.Any(false) }).bool()
				report_unused_inline: linter_severity(linter['reportUnusedInlineConfigs'] or {
					json2.Any(i64(0))
				})
				all_rules:            all_rules
				settings:             config_settings(root.as_map())
			},
		]
		file_config: file_config
	}
}

// resolve_with_bun runs the resolver with bun. `eslint` is resolved from the directory of the
// configuration (the project's own ESLint), or from VESLINT_ESLINT_DIR when it is set.
fn resolve_with_bun(config_path string, files []string, lookup bool) !string {
	return resolve_with_bun_inputs(config_path, files, lookup, '')
}

// resolve_with_bun_inputs is resolve_with_bun; with `inputs_path`, the resolver writes there what
// the resolution read (see eslint_resolver).
fn resolve_with_bun_inputs(config_path string, files []string, lookup bool, inputs_path string) !string {
	bun := os.find_abs_path_of_executable('bun') or {
		return error('reading ${config_path} needs `bun` in PATH: an ESLint configuration is JavaScript, and ESLint itself resolves it. Without bun, pass a resolved JSON (see --print-config)')
	}
	list_path := os.join_path(os.temp_dir(), 'veslint-files-${os.getpid()}.json')
	request := {
		'files': files
	}
	os.write_file(list_path, json2.encode(request)) or {
		return error('cannot write ${list_path}: ${err.msg()}')
	}
	defer {
		os.rm(list_path) or {}
	}
	mut process := os.new_process(bun)
	eslint_dir := os.getenv_opt('VESLINT_ESLINT_DIR') or { os.dir(config_path) }
	process.set_args(['--cwd=${os.abs_path(eslint_dir)}', '-e', eslint_resolver, '--', os.getwd(),
		config_path, list_path, if lookup { 'lookup' } else { 'config' }, inputs_path])
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	errors := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 || output == '' {
		return error('ESLint could not resolve ${config_path} (bun exited with code ${code}):\n${errors.trim_space()}')
	}
	return output
}

// loaded_from_resolved reads the resolved JSON: `configs` (each with `rules`, `linterOptions` and
// `languageOptions`),
// `files` (each with its `path` and either the index of its `config` or ESLint's `message` for a
// file it does not lint) and `pluginRules`. A relative `path` is relative to `base_dir`, the
// directory of the configuration or of the saved JSON.
fn loaded_from_resolved(text string, path string, base_dir string, files []string) !LoadedConfig {
	root := json2.decode[json2.Any](text) or {
		return error('${path}: the resolved configuration is not valid JSON (${err.msg()})')
	}
	if root !is map[string]json2.Any {
		return error('${path}: the resolved configuration must be an object')
	}
	object := root.as_map()
	// ESLint did not take the configuration: its own words.
	if message := object['error'] {
		return error('${path}: ${message.str()}')
	}
	mut configs := []ConfigEntry{}
	for item in (object['configs'] or { json2.Any([]json2.Any{}) }).as_array() {
		config := item.as_map()
		section := (config['rules'] or { json2.Any(map[string]json2.Any{}) }).as_map()
		linter := (config['linterOptions'] or { json2.Any(map[string]json2.Any{}) }).as_map()
		configs << ConfigEntry{
			language:             language_options(config)
			project_programs:     uses_project_programs(config)
			service_program_root: single_run_program_root(config, base_dir)
			projects:             named_projects_of(config, base_dir)
			setup:                rule_setup(section, path)!
			// ESLint's default for a flat configuration is "warn".
			report_unused:        linter_severity(linter['reportUnusedDisableDirectives'] or {
				json2.Any(i64(1))
			})
			no_inline_config:     (linter['noInlineConfig'] or { json2.Any(false) }).bool()
			report_unused_inline: linter_severity(linter['reportUnusedInlineConfigs'] or {
				json2.Any(i64(0))
			})
			all_rules:            section
			settings:             config_settings(config)
		}
	}
	mut by_path := map[string]json2.Any{}
	for item in (object['files'] or { json2.Any([]json2.Any{}) }).as_array() {
		entry := item.as_map()
		file_path := (entry['path'] or { json2.Any('') }).str()
		by_path[if os.is_abs_path(file_path) {
			file_path
		} else {
			os.abs_path(os.join_path(base_dir, file_path))
		}] = item
	}
	mut file_config := map[string]int{}
	mut file_notes := map[string]string{}
	for file in files {
		abs := os.abs_path(file)
		item := by_path[abs] or {
			return error('${path}: ${file} is not in the resolved configuration (its relative paths start at ${base_dir}); print it again with --print-config and save it inside the project')
		}
		entry := item.as_map()
		if message := entry['message'] {
			file_notes[abs] = message.str()
			continue
		}
		index := (entry['config'] or { json2.Any(i64(-1)) }).int()
		if index < 0 || index >= configs.len {
			return error('${path}: ${file} has no configuration in the resolved configuration')
		}
		file_config[abs] = index
	}
	return LoadedConfig{
		configs:        configs
		file_config:    file_config
		file_notes:     file_notes
		plugin_rules:   (object['pluginRules'] or { json2.Any([]json2.Any{}) }).as_array().map(it.str())
		strict_plugins: 'pluginRules' in object
		rule_defaults:  (object['ruleDefaults'] or { json2.Any(map[string]json2.Any{}) }).as_map()
		resolved:       portable_resolved(object, base_dir)
	}
}

// portable_resolved is the resolved JSON with the paths of the files relative to `base_dir`, so
// a saved copy next to the configuration works wherever the project is.
fn portable_resolved(object map[string]json2.Any, base_dir string) string {
	mut out := object.clone()
	// The tsconfig files of `parserOptions.project`, relative to `base_dir` too.
	mut configs := []json2.Any{}
	for item in (object['configs'] or { json2.Any([]json2.Any{}) }).as_array() {
		configs << portable_projects(item, base_dir)
	}
	if 'configs' in object {
		out['configs'] = json2.Any(configs)
	}
	mut files := []json2.Any{}
	for item in (object['files'] or { json2.Any([]json2.Any{}) }).as_array() {
		mut entry := item.as_map().clone()
		file_path := (entry['path'] or { json2.Any('') }).str()
		if file_path.starts_with(base_dir + os.path_separator) {
			entry['path'] = json2.Any(portable_relative(file_path[base_dir.len + 1..]))
		}
		files << json2.Any(entry)
	}
	out['files'] = json2.Any(files)
	return encode_ordered(json2.Any(out))
}

// portable_relative writes a relative path with `/`, as on Linux, so that the same configuration
// gives the same JSON on Windows, which reads `/` back too.
fn portable_relative(path string) string {
	$if windows {
		return path.replace('\\', '/')
	}
	return path
}

// portable_projects is a configuration of the resolved JSON with the paths of
// `languageOptions.parserOptions.project` relative to `base_dir`.
fn portable_projects(config json2.Any, base_dir string) json2.Any {
	if config !is map[string]json2.Any {
		return config
	}
	language := config.as_map()['languageOptions'] or { return config }
	if language !is map[string]json2.Any {
		return config
	}
	parser := language.as_map()['parserOptions'] or { return config }
	if parser !is map[string]json2.Any {
		return config
	}
	mut new_parser := parser.as_map().clone()
	// The tsconfigRootDir the resolver adds for the project service, relative too.
	if root := new_parser['tsconfigRootDir'] {
		if root is string {
			if root == base_dir {
				new_parser['tsconfigRootDir'] = json2.Any('.')
			} else if root.starts_with(base_dir + os.path_separator) {
				new_parser['tsconfigRootDir'] = json2.Any(portable_relative(root[base_dir.len + 1..]))
			}
		}
	}
	project := new_parser['project'] or { json2.Any(json2.null) }
	if project !is []json2.Any {
		if 'tsconfigRootDir' !in new_parser {
			return config
		}
		mut new_language := language.as_map().clone()
		new_language['parserOptions'] = json2.Any(new_parser)
		mut new_config := config.as_map().clone()
		new_config['languageOptions'] = json2.Any(new_language)
		return json2.Any(new_config)
	}
	mut paths := []json2.Any{}
	for item in project.as_array() {
		path := item.str()
		paths << json2.Any(if path.starts_with(base_dir + os.path_separator) {
			portable_relative(path[base_dir.len + 1..])
		} else {
			path
		})
	}
	new_parser['project'] = json2.Any(paths)
	mut new_language := language.as_map().clone()
	new_language['parserOptions'] = json2.Any(new_parser)
	mut new_config := config.as_map().clone()
	new_config['languageOptions'] = json2.Any(new_language)
	return json2.Any(new_config)
}

// encode_ordered writes a JSON value with the keys of its objects in their own order, which
// json2.encode sorts: the order of `languageOptions.globals` is the order ESLint declares the
// globals of a file in.
fn encode_ordered(value json2.Any) string {
	return match value {
		map[string]json2.Any {
			mut parts := []string{cap: value.len}
			for key, item in value {
				parts << json2.encode(key) + ':' + encode_ordered(item)
			}
			'{' + parts.join(',') + '}'
		}
		[]json2.Any {
			'[' + value.map(encode_ordered(it)).join(',') + ']'
		}
		else {
			value.json_str()
		}
	}
}

// linter_severity reads a severity of linterOptions: a number, a name, or a boolean (true = warn).
fn linter_severity(value json2.Any) int {
	return match value.json_str() {
		'0', '"off"', 'false' { 0 }
		'2', '"error"' { 2 }
		else { 1 }
	}
}

// only_rule_config is `loaded` for `--rule rule`: of the rules of each configuration, that one
// alone, with its severity and options there; on, with the options the configuration gives it
// when it turns it off (or with its default ones), when the configuration does not run it.
fn only_rule_config(loaded LoadedConfig, rule string) LoadedConfig {
	mut configs := []ConfigEntry{cap: loaded.configs.len}
	for entry in loaded.configs {
		mut chosen := entry.setup.rules.filter(it.name == rule)
		if chosen.len == 0 {
			chosen = [
				RuleConfig{
					name:    rule
					error:   true
					options: entry.setup.base_options[rule] or { rules.decoded_default_options(rule) }
				},
			]
		}
		configs << ConfigEntry{
			...entry
			setup: RuleSetup{
				rules:        chosen
				base_options: entry.setup.base_options
				off_problems: entry.setup.off_problems
			}
		}
	}
	if configs.len == 0 {
		// Every file is one the configuration does not lint: their notes say so.
		configs << ConfigEntry{
			setup: RuleSetup{
				rules: [RuleConfig{
					name:    rule
					error:   true
					options: rules.decoded_default_options(rule)
				}]
			}
		}
	}
	return LoadedConfig{
		...loaded
		configs:   configs
		only_rule: rule
	}
}
