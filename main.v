module main

import json2
import offsets
import os
import rules
import strings
import time
import treesitter
import tsgo
import svelte
import vue

// veslint: parses TypeScript with tree-sitter and asks tsgo (`tsc --api`) for the types.
// Flow from PROMPT.md §4.

const usage = 'usage: veslint <file.ts | directory>... [--project <tsconfig.json>] [--all-identifiers] [--bench] [--per-identifier] [--rule <rule> [--no-config-lookup] | --config <eslint.config.mjs | rules.json> [--print-config]] [--fix] [--fixes | --summary] | veslint --server | veslint --version'
const default_timeout_ms = 30000
// ESLint's MAX_AUTOFIX_PASSES.
const max_fix_passes = 10

struct Options {
mut:
	files           []string
	project         string
	all_identifiers bool
	bench           bool
	per_identifier  bool
	fixes           bool // --fixes: print the fix and the suggestions of each finding
	fix             bool // --fix: apply the fixes and write the files, like `eslint --fix`
	print_config    bool // --print-config: print the resolved configuration and exit
	summary         bool // --summary: a table of the rules that report problems, not a line per problem
	server          bool // --server: lint the requests of an editor until stdin ends (server.v)
	// --no-config-lookup: --rule runs with the default options of the rule, not the ones of the
	// closest ESLint configuration.
	no_config_lookup bool
	rules            []RuleConfig // the rules of --rule or of every configuration of --config
	ignored          []string     // active rules from --config that veslint does not have
	loaded           LoadedConfig // the configuration of each file (--rule: a single one)
}

// FileWork gathers what veslint knows about a file before querying tsgo.
struct FileWork {
	path     string // as given on the command line
	abs_path string
	tsconfig string
	idents   []treesitter.Ident
	offsets  []int // UTF-16 offset of each identifier (what is sent to tsgo)
	display  []offsets.DisplayPos
	src      string // content without the BOM, as Node decodes it
	not_utf8 bool   // the bytes are not valid UTF-8: tsgo is served `src`
	// A .vue file: tsgo has its script in a virtual twin at ts_path (vue_files.v), with the text
	// twin_code; ts_path is abs_path for any other file. A .svelte file too (svelte_files.v).
	vue       bool
	svelte    bool
	ts_path   string
	twin_code string
}

// BenchReport holds the per-phase timings that `--bench` writes to stderr (PROMPT.md §8).
struct BenchReport {
mut:
	mode                    string
	files                   int
	identifiers             int
	read_parse_ms           f64
	query_ms                f64
	offsets_ms              f64
	spawn_version_init_ms   f64
	update_snapshot_ms      f64
	symbol_requests         int
	symbols_ms              f64
	symbols_max_ms          f64
	type_requests           int
	types_ms                f64
	types_max_ms            f64
	type_to_string_requests int
	base_type_requests      int
	type_cache_hits         int
	describe_types_ms       f64
	total_ms                f64
	// Time of each batch; empty with --per-identifier, which has no batches.
	symbol_batches_ms []f64
	type_batches_ms   []f64
	// --rule mode.
	rule_checked   int
	rule_nodes     int
	rule_unmatched int
	rule_findings  int
	rule_types_ms  f64
	rule_eval_ms   f64
	tsgo_requests  int
	// Every rule that ran, `<rule> <ms>`, slowest first.
	slowest_rules []string
}

fn (mut b BenchReport) add_symbols(elapsed f64) {
	b.symbol_requests++
	b.symbols_ms += elapsed
	if elapsed > b.symbols_max_ms {
		b.symbols_max_ms = elapsed
	}
}

fn (mut b BenchReport) add_types(elapsed f64) {
	b.type_requests++
	b.types_ms += elapsed
	if elapsed > b.types_max_ms {
		b.types_max_ms = elapsed
	}
}

fn ms(d time.Duration) f64 {
	return f64(d) / f64(time.millisecond)
}

fn main() {
	os.signal_ignore(.pipe)
	args := os.args[1..]
	if '-h' in args || '--help' in args {
		println(usage)
		return
	}
	if args == ['--version'] {
		println('veslint ${version}')
		return
	}
	opts := parse_args(args) or {
		eprintln('veslint: ${err.msg()}')
		eprintln(usage)
		exit(2)
	}
	timeout := timeout_from_env() or {
		eprintln('veslint: ${err.msg()}')
		exit(2)
	}
	cpus := cpus_from_env() or {
		eprintln('veslint: ${err.msg()}')
		exit(2)
	}
	// Before tsgo starts (cpus.v), and after the configuration of a command line is resolved: that
	// bun runs on every CPU (the one of a request to a server, on the server's).
	limit_cpus(cpus)
	if opts.server {
		serve(timeout)
		return
	}
	if opts.print_config {
		println(opts.loaded.resolved)
		return
	}
	if opts.ignored.len > 0 {
		eprintln(ignored_rules_warning(opts.ignored))
	}
	problems := run(opts, timeout) or {
		eprintln('veslint: ${err.msg()}')
		exit(1)
	}
	if problems > 0 {
		exit(1)
	}
}

fn parse_args(args []string) !Options {
	mut opts := Options{}
	mut rule := ''
	mut config := ''
	mut targets := []string{} // the files and directories, in their order
	mut i := 0
	for i < args.len {
		arg := args[i]
		match arg {
			'--project' {
				if i + 1 >= args.len {
					return error('missing path after --project')
				}
				opts.project = args[i + 1]
				i++
			}
			'--all-identifiers' {
				opts.all_identifiers = true
			}
			'--bench' {
				opts.bench = true
			}
			'--per-identifier' {
				opts.per_identifier = true
			}
			'--fixes' {
				opts.fixes = true
			}
			'--fix' {
				opts.fix = true
			}
			'--print-config' {
				opts.print_config = true
			}
			'--summary' {
				opts.summary = true
			}
			'--server' {
				opts.server = true
			}
			'--no-config-lookup' {
				opts.no_config_lookup = true
			}
			'--rule' {
				if i + 1 >= args.len {
					return error('missing rule name after --rule')
				}
				if rule != '' {
					return error('--rule takes a single rule per run; for several, use --config')
				}
				rule = args[i + 1]
				if rule !in rules.names {
					return error('unknown rule: ${rule} (available: ${rules.names.join(', ')})')
				}
				i++
			}
			'--config' {
				if i + 1 >= args.len {
					return error('missing path after --config')
				}
				if config != '' {
					return error('--config takes a single file')
				}
				config = args[i + 1]
				i++
			}
			else {
				if arg.starts_with('-') {
					return error('unknown option: ${arg}')
				}
				if !os.is_dir(arg) && !is_typescript_path(arg) {
					return error('${arg}: ${only_typescript}')
				}
				targets << arg
			}
		}
		i++
	}
	if opts.server {
		// Each request says what to lint, with which configuration (server.v).
		if args.len > 1 {
			return error('--server takes no files and no other options: each request gives them')
		}
		return opts
	}
	if targets.len == 0 {
		return error('missing file to analyze')
	}
	// A directory brings its TypeScript files (directories.v); the ones ESLint's configuration does
	// not lint are dropped below, without a word, as ESLint skips them.
	mut dirs := []string{}
	mut from_dir := map[string]string{} // the directory each file of a directory comes from (absolute path)
	mut seen := map[string]bool{}
	for target in targets {
		if !os.is_dir(target) {
			seen[os.abs_path(target)] = true
			opts.files << target
			continue
		}
		dirs << target
		found := directory_files(target)
		if found.len == 0 {
			return error('No files matching the pattern "${target}" were found.')
		}
		for file in found {
			abs := os.abs_path(file)
			if abs in seen {
				continue
			}
			seen[abs] = true
			from_dir[abs] = target
			opts.files << file
		}
	}
	// With a directory and neither --rule nor --config, ESLint's configuration is the one the
	// eslint command would use: ESLint finds the closest eslint.config.* of each file.
	mut lookup := false
	if dirs.len > 0 && rule == '' && config == '' {
		config = find_flat_config(dirs[0]) or {
			return error('no ESLint configuration (${flat_config_names.join(', ')}) in ${dirs[0]} or a directory above it; give one with --config, or a rule with --rule')
		}
		lookup = true
	}
	if opts.summary && opts.fixes {
		return error('--summary and --fixes cannot be combined: --summary prints no problem lines')
	}
	if rule != '' && config != '' {
		return error('--rule and --config cannot be combined')
	}
	if (rule != '' || config != '') && (opts.all_identifiers || opts.per_identifier) {
		return error('--all-identifiers and --per-identifier belong to type mode; they cannot be combined with --rule or --config')
	}
	if opts.no_config_lookup && rule == '' {
		return error('--no-config-lookup is for --rule')
	}
	// --rule with the closest ESLint configuration: the rule alone, with what the configuration
	// says of it (options, languageOptions, settings, the files it lints).
	rule_config := if rule != '' && !opts.no_config_lookup {
		find_flat_config(if dirs.len > 0 { dirs[0] } else { os.dir(os.abs_path(opts.files[0])) }) or {
			''
		}
	} else {
		''
	}
	if rule_config != '' {
		loaded := load_config_with(rule_config, opts.files, true) or {
			return error('${err.msg()}\n(--rule takes the options of the rule from ${rule_config}; --no-config-lookup runs it with its default options)')
		}
		opts.loaded = only_rule_config(loaded, rule)
		if from_dir.len > 0 {
			drop_unlinted(mut opts, from_dir, dirs)!
		}
		opts.rules = [opts.loaded.configs[0].setup.rules[0]]
	} else if rule != '' {
		opts.rules = [RuleConfig{
			name:    rule
			error:   true
			options: rules.decoded_default_options(rule)
		}]
		mut file_config := map[string]int{}
		for file in opts.files {
			file_config[os.abs_path(file)] = 0
		}
		opts.loaded = LoadedConfig{
			configs:     [ConfigEntry{
				setup:                RuleSetup{
					rules:        opts.rules
					base_options: {
						rule: rules.decoded_default_options(rule)
					}
				}
				service_program_root: single_run_program_root(map[string]json2.Any{}, '')
			}]
			file_config: file_config
			only_rule:   rule
		}
	}
	if opts.print_config && config == '' {
		return error('--print-config needs --config with an ESLint configuration file')
	}
	if config != '' {
		opts.loaded = load_config_with(config, opts.files, lookup)!
		if from_dir.len > 0 && !opts.print_config {
			drop_unlinted(mut opts, from_dir, dirs)!
		}
		// The rules and the ignored ones of every configuration, for the mode and the warning.
		for entry in opts.loaded.configs {
			for r in entry.setup.rules {
				if !opts.rules.any(it.name == r.name) {
					opts.rules << r
				}
			}
			for id in entry.setup.ignored {
				if id !in opts.ignored {
					opts.ignored << id
				}
			}
		}
		if opts.rules.len == 0 && !opts.print_config {
			return error('${config}: does not enable any veslint rule (${rules.names.join(', ')})')
		}
	}
	if opts.summary && opts.rules.len == 0 {
		return error('--summary needs rules: --rule, --config, or a directory with an ESLint configuration')
	}
	return opts
}

// drop_unlinted takes out of the run the files of a directory that ESLint does not lint (ignored by
// the configuration, or matched by none of its `files`), as ESLint skips them when it walks a
// directory. A directory left without files is an error, as in ESLint.
fn drop_unlinted(mut opts Options, from_dir map[string]string, dirs []string) ! {
	mut kept := []string{}
	mut linted := map[string]bool{}
	for file in opts.files {
		abs := os.abs_path(file)
		if dir := from_dir[abs] {
			if abs in opts.loaded.file_notes {
				opts.loaded.file_notes.delete(abs)
				continue
			}
			linted[dir] = true
		}
		kept << file
	}
	for dir in dirs {
		if dir !in linted {
			return error('You are linting "${dir}", but all of the files matching the glob pattern "${dir}" are ignored.')
		}
	}
	opts.files = kept
}

// timeout_from_env lowers the per-request timeout (30 s by default), to test the timeout case of
// §9 without waiting.
fn timeout_from_env() !time.Duration {
	raw := os.getenv('VESLINT_TIMEOUT_MS').trim_space()
	if raw == '' {
		return default_timeout_ms * time.millisecond
	}
	value := raw.int()
	if value <= 0 || value.str() != raw {
		return error('VESLINT_TIMEOUT_MS must be a positive integer (got `${raw}`)')
	}
	return value * time.millisecond
}

// run returns how many errors the rules found, which decide the exit code (always 0 in type
// mode).
fn run(opts Options, timeout time.Duration) !int {
	if opts.rules.len > 0 {
		return run_rules(opts, timeout)!
	}
	total := time.new_stopwatch()
	mut bench := BenchReport{
		mode: if opts.per_identifier {
			'one request per identifier'
		} else {
			'one batch per file'
		}
	}
	mut project_override := ''
	if opts.project != '' {
		if !os.is_file(opts.project) {
			return error('tsconfig ${opts.project} does not exist')
		}
		project_override = os.abs_path(opts.project)
	}
	parser := treesitter.new_parser()!
	// .tsx files use the grammar's tsx dialect (JSX, and no `<T>x` assertions).
	tsx_parser := treesitter.new_tsx_parser()!
	defer {
		parser.close()
		tsx_parser.close()
	}
	// Steps 1–5: read, strip the BOM, parse, collect identifiers, convert offsets and find the
	// tsconfig of each file.
	mut works := []FileWork{cap: opts.files.len}
	mut vue_parsers := VueParsers{}
	mut svelte_parsers := SvelteParsers{}
	defer {
		vue_parsers.close()
		svelte_parsers.close()
	}
	for path in opts.files {
		if rules.is_svelte_path(path) {
			work := prepare_svelte_file(mut svelte_parsers, parser, path, project_override,
				opts.all_identifiers, opts.loaded.svelte_parse_options(os.abs_path(path)), mut
				bench)!
			if work.svelte {
				works << work
			}
			continue
		}
		if rules.is_vue_path(path) {
			work := prepare_vue_file(mut vue_parsers, parser, path, project_override, opts.all_identifiers,
				opts.loaded.vue_parse_options(os.abs_path(path)), mut bench)!
			if work.vue {
				works << work
			}
			continue
		}
		works << prepare_file(if treesitter.uses_jsx_dialect(path) { tsx_parser } else { parser }, path,
			project_override, opts.all_identifiers, mut bench)!
	}
	if bench.identifiers == 0 {
		// Nothing to query: no need to start tsgo.
		print_bench(opts, mut bench, total)
		return 0
	}
	mut tsconfigs := []string{}
	for w in works {
		if w.tsconfig !in tsconfigs {
			tsconfigs << w.tsconfig
		}
	}
	// Step 6: start tsgo, check the version, initialize and createSnapshot.
	mut sw := time.new_stopwatch()
	mut served := map[string]string{}
	mut virtual := map[string]string{}
	for w in works {
		if w.vue || w.svelte {
			virtual[w.ts_path] = w.twin_code
		} else if w.not_utf8 {
			served[w.abs_path] = w.src
		}
	}
	mut client := if virtual.len > 0 {
		tsgo.start_virtual(tsgo.binary_path(), os.dir(tsconfigs[0]), timeout, served, virtual)!
	} else {
		tsgo.start_with_files(tsgo.binary_path(), os.dir(tsconfigs[0]), timeout, served)!
	}
	defer {
		client.shutdown()
	}
	_ = client.initialize()!
	if virtual.len > 0 {
		mut twins := map[string][]string{}
		for w in works {
			if w.vue || w.svelte {
				twins[w.tsconfig] << w.ts_path
			}
		}
		include_twins(mut client, twins)!
	}
	bench.spawn_version_init_ms = ms(sw.elapsed())
	sw.restart()
	snap := client.create_snapshot(tsconfigs)!
	bench.update_snapshot_ms = ms(sw.elapsed())
	projects := map_projects(tsconfigs, snap)!
	// Steps 7–10, file by file.
	mut cache := TypeCache{}
	for w in works {
		if w.idents.len == 0 {
			continue
		}
		project := projects[w.tsconfig]
		symbols, types := query_file(mut client, snap.snapshot, project, w, opts.per_identifier, mut
			bench)!
		check_invariant(w, symbols, opts.all_identifiers)!
		sw.restart()
		mut out := strings.new_builder(w.idents.len * 48)
		for i, id in w.idents {
			d := w.display[i]
			desc := cache.describe(mut client, snap.snapshot, project, types[i], mut bench)!
			out.writeln('${w.path}:${d.line}:${d.col}\t${id.text}\t${desc}')
		}
		bench.describe_types_ms += ms(sw.elapsed())
		print(out.str())
	}
	print_bench(opts, mut bench, total)
	return 0
}

fn print_bench(opts Options, mut bench BenchReport, total time.StopWatch) {
	bench.total_ms = ms(total.elapsed())
	if opts.bench {
		eprintln(json2.encode(bench))
	}
}

struct RuleFile {
	path     string // as given on the command line
	abs_path string
	tsconfig string
	// The tsconfig files `parserOptions.project` names for it: the first one that has the file is
	// its tsconfig, decided with the snapshot (assign_named_projects).
	named    []string
	src      string // content without the BOM, as Node decodes it
	has_bom  bool
	not_utf8 bool   // the bytes are not valid UTF-8: tsgo is served `src`
	note     string // ESLint's message for a file it does not lint (ignored, or without configuration)
	// A .vue file: tsgo has its script in a virtual twin, at ts_path with the text twin_code
	// (vue_files.v); ts_path is abs_path for any other file. A .svelte file too (svelte_files.v).
	vue       bool
	svelte    bool
	ts_path   string
	twin_code string
	// svelte_options: the runes options a .svelte file is parsed with (svelte_parse_options).
	svelte_options svelte.ParseOptions
	// vue_options: the vueFeatures a .vue file is parsed with (vue_parse_options).
	vue_options vue.Options
	// A `.svelte.ts` module: tsgo reads its virtual code instead of the file (svelte/module.v).
	module svelte.ModuleVirtual
}

// run_rules applies the rules to the files and prints one line per problem:
// `path:line:col<TAB>rule<TAB>messageId<TAB>message`, with `<TAB>warning` at the end for a finding
// of a rule set to "warn" (README.md, "The line format"). Returns how many errors there were
// (findings of rules set to "warn" do not count).
fn run_rules(opts Options, timeout time.Duration) !int {
	total := time.new_stopwatch()
	selected := opts.rules.map(it.name)
	lint_configs := []rules.LintConfig{len: opts.loaded.configs.len, init: opts.loaded.lint_config(index)}
	mut bench := BenchReport{
		mode: if selected.len == 1 {
			'rule ${selected[0]}'
		} else {
			'rules ${selected.join(', ')}'
		}
	}
	mut project_override := ''
	if opts.project != '' {
		if !os.is_file(opts.project) {
			return error('tsconfig ${opts.project} does not exist')
		}
		project_override = os.abs_path(opts.project)
	}
	parser := treesitter.new_parser()!
	// .tsx files use the grammar's tsx dialect (JSX, and no `<T>x` assertions).
	tsx_parser := treesitter.new_tsx_parser()!
	defer {
		parser.close()
		tsx_parser.close()
	}
	mut files := []RuleFile{cap: opts.files.len}
	mut tsconfigs := []string{}
	mut vue_parsers := VueParsers{}
	mut svelte_parsers := SvelteParsers{}
	defer {
		vue_parsers.close()
		svelte_parsers.close()
	}
	for path in opts.files {
		abs_path := os.abs_path(path)
		if note := opts.loaded.file_notes[abs_path] {
			// A file ESLint does not lint: only its message is printed.
			files << RuleFile{
				path: path
				note: note
			}
			continue
		}
		src, has_bom, not_utf8 := read_source(path)!
		is_vue := rules.is_vue_path(path)
		is_svelte := rules.is_svelte_path(path)
		mut twin_code := ''
		svelte_options := if is_svelte {
			opts.loaded.svelte_parse_options(abs_path)
		} else {
			svelte.ParseOptions{}
		}
		vue_options := if is_vue { opts.loaded.vue_parse_options(abs_path) } else { vue.Options{} }
		if is_vue {
			code, linted := vue_parsers.twin_code(src, vue_options) or {
				return error('${path}: ${err.msg()}')
			}
			if !linted {
				eprintln(vue_javascript_warning(path))
				continue
			}
			twin_code = code
		} else if is_svelte {
			code, linted := svelte_parsers.twin_code(src, svelte_options) or {
				return error('${path}: ${err.msg()}')
			}
			if !linted {
				eprintln(svelte_javascript_warning(path))
				continue
			}
			twin_code = code
		}
		module := if svelte.is_svelte_module_path(path) {
			svelte_parsers.module_virtual(src) or { return error('${path}: ${err.msg()}') }
		} else {
			svelte.ModuleVirtual{}
		}
		named := if project_override == '' {
			opts.loaded.named_projects(abs_path)
		} else {
			[]string{}
		}
		tsconfig := if named.len > 0 {
			''
		} else if project_override != '' {
			project_override
		} else {
			find_tsconfig(abs_path)!
		}
		for t in named {
			if t !in tsconfigs {
				tsconfigs << t
			}
		}
		if tsconfig != '' && tsconfig !in tsconfigs {
			tsconfigs << tsconfig
		}
		files << RuleFile{
			path:           path
			abs_path:       abs_path
			tsconfig:       tsconfig
			named:          named
			src:            src
			has_bom:        has_bom
			not_utf8:       not_utf8
			vue:            is_vue
			svelte:         is_svelte
			ts_path:        if is_vue {
				rules.vue_twin_path(abs_path)
			} else if is_svelte {
				rules.svelte_twin_path(abs_path)
			} else {
				abs_path
			}
			twin_code:      twin_code
			svelte_options: svelte_options
			vue_options:    vue_options
			module:         module
		}
	}
	bench.files = files.len
	if tsconfigs.len == 0 {
		// ESLint lints none of the files: only its message for each one.
		mut summary := RuleSummary{}
		for f in files {
			if opts.summary {
				summary.add(rules.problem_rule, f.path, true)
			} else {
				println(note_line(f.path, f.note))
			}
		}
		print(summary.table())
		eprintln('${files.len} problems in ${files.len} files (${files.len} of them warnings)')
		return 0
	}
	mut sw := time.new_stopwatch()
	mut served := map[string]string{}
	mut virtual := map[string]string{}
	for f in files {
		if f.vue || f.svelte {
			virtual[f.ts_path] = f.twin_code
		} else if f.module.inserted > 0 {
			served[f.abs_path] = f.module.code
		} else if f.not_utf8 {
			served[f.abs_path] = f.src
		}
	}
	mut client := if virtual.len > 0 {
		tsgo.start_virtual(tsgo.binary_path(), os.dir(tsconfigs[0]), timeout, served, virtual)!
	} else {
		tsgo.start_with_files(tsgo.binary_path(), os.dir(tsconfigs[0]), timeout, served)!
	}
	defer {
		client.shutdown()
	}
	_ = client.initialize()!
	if virtual.len > 0 {
		mut twins := map[string][]string{}
		for f in files {
			if (f.vue || f.svelte) && f.tsconfig != '' {
				twins[f.tsconfig] << f.ts_path
			}
		}
		include_twins(mut client, twins)!
	}
	bench.spawn_version_init_ms = ms(sw.elapsed())
	sw.restart()
	// When no rule of the configurations needs types, tsgo only parses the tsconfigs and builds no
	// program: a checker makes a snapshot if a comment turns on a rule that needs them, or if an
	// `await` may be a name (Checker.make_snapshot). --fix keeps the snapshot of every pass, as
	// tsgo has to be told of each file it writes.
	lazy := !opts.fix && !configs_need_types(lint_configs)
	mut snap := if lazy {
		config_snapshot(mut client, tsgo.UpdateSnapshotResponse{ snapshot: no_snapshot }, tsconfigs)!
	} else {
		client.create_snapshot(tsconfigs)!
	}
	opened := assign_named_projects(mut files, snap)!
	if opened.len > 0 {
		if lazy {
			snap = config_snapshot(mut client, snap, opened)!
		} else {
			previous_snapshot := snap.snapshot
			snap = client.update_snapshot_files(snap, opened, tsgo.FileChangeSet{})!
			if snap.snapshot != previous_snapshot {
				client.release_snapshot(previous_snapshot)!
			}
		}
		tsconfigs << opened
	}
	bench.update_snapshot_ms = ms(sw.elapsed())
	mut projects := map_projects(tsconfigs, snap)!
	mut checkers := map[string]&rules.Checker{}
	// The index of the last file of each project: without --fix (whose passes make new snapshots
	// and checkers), the checker of a project is dropped after it, so that a run over files of many
	// tsconfigs does not keep every checker alive (the garbage collector walks what is alive).
	mut last_of_project := map[string]int{}
	if !opts.fix {
		for index, f in files {
			if f.note == '' {
				last_of_project[projects[f.tsconfig]] = index
			}
		}
	}
	mut problems := 0
	mut warnings := 0
	mut fixed_files := 0
	mut stats := rules.Stats{}
	mut summary := RuleSummary{}
	for file_index, f in files {
		if f.note != '' {
			if opts.summary {
				summary.add(rules.problem_rule, f.path, true)
			} else {
				println(note_line(f.path, f.note))
			}
			problems++
			warnings++
			continue
		}
		config_index := opts.loaded.file_config[f.abs_path] or { 0 }
		mut lint_config := lint_configs[config_index]
		if f.abs_path in opts.loaded.file_runes {
			// A runes function of the svelteConfig: what it gave for this file (file_language).
			lint_config = rules.LintConfig{
				...lint_config
				language: opts.loaded.file_language(f.abs_path, lint_config.language)
			}
		}
		// In a single run, the project service leaves the file to a Program made for its tsconfig,
		// whose current directory is the one ESLint runs in, when the tsconfig is the one veslint
		// lints the file with; only for the text on disk (the first pass of --fix).
		service_directory := lint_config.program_directory
		if config_index < opts.loaded.configs.len && is_single_run(opts.fix) {
			root := opts.loaded.configs[config_index].service_program_root
			if root != '' && f.tsconfig != '' && single_run_tsconfig(f.abs_path, root) == f.tsconfig {
				lint_config.program_directory = os.getwd()
			}
		}
		mut src := f.src
		mut has_bom := f.has_bom
		mut module := f.module
		mut result := rules.FileLint{}
		// The document of a .vue file, parsed again after each pass of --fix.
		mut doc := &vue.Document(unsafe { nil })
		if f.vue {
			doc = vue_parsers.parse(src, f.vue_options) or { return error('${f.path}: ${err.msg()}') }
		}
		// The document of a .svelte file, the same way.
		mut sdoc := &svelte.Document(unsafe { nil })
		if f.svelte {
			sdoc = svelte_parsers.parse(src, f.svelte_options) or { return error('${f.path}: ${err.msg()}') }
		}
		// --fix ports ESLint's verifyAndFix: lint, apply the fixes that do not overlap, and lint the
		// result again, up to 10 passes or until two passes give the same text. tsgo only reads
		// files, so each pass is written to disk and a new snapshot is taken.
		mut pass := 0
		mut syntax_baseline := -1
		mut previous := ''
		mut second_previous := ''
		for {
			pass++
			if pass > 1 {
				lint_config.program_directory = service_directory
			}
			project := projects[f.tsconfig]
			if project !in checkers {
				mut new_checker := rules.new_checker(client, snap.snapshot, project, project_options(snap,
					project))!
				new_checker.set_project_directory(os.dir(f.tsconfig))
				if lazy {
					new_checker.defer_snapshot(project)
				}
				checkers[project] = new_checker
			}
			mut checker := checkers[project] or { return error('no checker for ${project}') }
			checker.set_has_bom(has_bom)
			// A fix may give code TypeScript cannot parse: from the second pass on, a parsing error
			// that was not in the file is reported alone and stops the fixes, as ESLint does.
			if opts.fix {
				if pass == 1 {
					// The checker may come from the passes of another file.
					checker.check_syntax(-1)
					syntax_baseline = checker.syntax_error_count(f.ts_path)
				} else {
					checker.check_syntax(syntax_baseline)
				}
			}
			if f.vue {
				checker.set_vue(doc, f.ts_path)
			} else if f.svelte {
				checker.set_svelte(sdoc, f.ts_path, svelte_parsers.parsers)
			} else if module.inserted > 0 {
				checker.set_svelte_module(src, module.code, module.at, module.inserted)
			}
			result = checker.lint_file(if (f.vue && doc.script.jsx)
				|| (!f.vue && !f.svelte && treesitter.uses_jsx_dialect(f.path)) {
				tsx_parser
			} else {
				parser
			},
				lint_config, src, f.abs_path, mut stats) or {
				return error('${f.path}: ${err.msg()}')
			}
			if !opts.fix || pass > max_fix_passes {
				break
			}
			// ESLint does not fix a file it cannot parse (a fix of the previous pass may have broken it).
			if result.parsing_error {
				break
			}
			if result.syntax_errors {
				if result.findings.any(it.has_fix) {
					eprintln('warning: ${f.path}: not fixed, because tree-sitter found syntax errors')
				}
				break
			}
			fixed, output := rules.apply_fixes(src, result.findings)
			if !fixed {
				break
			}
			second_previous = previous
			previous = src
			src = output
			// A fix of the range [-1, 0] removes the BOM, which is before the text (unicode-bom).
			if result.findings.any(it.has_fix && it.fix.start < 0) {
				has_bom = false
			}
			os.write_file(f.path, if has_bom { offsets.utf8_bom + src } else { src }) or {
				return error('cannot write ${f.path}: ${err.msg()}')
			}
			if f.vue {
				// The twin gets the code of the fixed script.
				doc.free()
				doc = vue_parsers.parse(src, f.vue_options) or { return error('${f.path}: ${err.msg()}') }
				client.serve(f.ts_path, doc.script.code)
			} else if f.svelte {
				sdoc.free()
				sdoc = svelte_parsers.parse(src, f.svelte_options) or { return error('${f.path}: ${err.msg()}') }
				client.serve(f.ts_path, sdoc.virtual_code)
			} else if f.module.inserted > 0 || module.inserted > 0 {
				// The module's virtual code is made again from the fixed text.
				module = svelte_parsers.module_virtual(src) or {
					return error('${f.path}: ${err.msg()}')
				}
				client.serve(f.abs_path, module.code)
			} else {
				// What is on disk now is valid UTF-8: tsgo reads it from there.
				client.stop_serving(f.abs_path)
			}
			if pass == 1 {
				fixed_files++
			}
			previous_snapshot := snap.snapshot
			snap = client.update_snapshot_changed(snap, [f.ts_path])!
			projects = map_projects(tsconfigs, snap)!
			checkers.clear()
			if snap.snapshot != previous_snapshot {
				client.release_snapshot(previous_snapshot)!
			}
			if pass > 1 && src == second_previous {
				eprintln('warning: ${f.path}: circular fixes; stopped after ${pass} passes')
				pass = max_fix_passes
			}
		}
		if !opts.fix {
			project := projects[f.tsconfig]
			if last_of_project[project] == file_index {
				checkers.delete(project)
			}
		}
		report := file_report(f.path, src, result, opts.fixes, doc, sdoc)
		if f.vue {
			doc.free()
		}
		if f.svelte {
			sdoc.free()
		}
		eprint(report.stderr)
		if opts.summary {
			for finding in result.findings {
				summary.add(finding.rule, f.path, finding.severity == 1)
			}
		} else {
			print(report.stdout)
		}
		problems += report.problems
		warnings += report.warnings
	}
	bench.read_parse_ms = stats.parse_ms
	bench.rule_checked = stats.checked
	bench.rule_nodes = stats.nodes
	bench.rule_unmatched = stats.unmatched
	bench.rule_findings = stats.findings
	bench.rule_types_ms = stats.types_ms
	bench.rule_eval_ms = stats.eval_ms
	bench.tsgo_requests = client.request_count()
	mut by_time := stats.rule_ms.keys()
	by_time.sort_with_compare(fn [stats] (a &string, b &string) int {
		ta := stats.rule_ms[*a]
		tb := stats.rule_ms[*b]
		return if ta > tb {
			-1
		} else if ta < tb {
			1
		} else {
			compare_strings(a, b)
		}
	})
	bench.slowest_rules = by_time.map('${it} ${stats.rule_ms[it]:.1f}')
	print(summary.table())
	fixed_note := if opts.fix { '; ${fixed_files} files fixed' } else { '' }
	eprintln(summary_line(problems, files.len, warnings) + fixed_note)
	print_bench(opts, mut bench, total)
	return problems - warnings
}

// ignored_rules_warning is the warning about the active rules of a configuration that veslint
// does not have.
fn ignored_rules_warning(ignored []string) string {
	shown := ignored#[..8].join(', ')
	more := if ignored.len > 8 { ', … (${ignored.len - 8} more)' } else { '' }
	return 'warning: veslint does not have ${ignored.len} of the active rules of the configuration and ignores them: ${shown}${more}'
}

// summary_line is the last line a run with rules prints on stderr.
fn summary_line(problems int, files int, warnings int) string {
	of_which := if warnings > 0 { ' (${warnings} of them warnings)' } else { '' }
	return '${problems} problems in ${files} files${of_which}'
}

// FileReport is what a run with rules prints for a file: its findings on stdout and the warnings
// about it on stderr.
struct FileReport {
	stdout   string
	stderr   string
	problems int
	warnings int // the findings of rules set to "warn"
}

// file_report writes the findings of a file (`path` as it is printed) and the warnings about how
// it was read.
fn file_report(path string, src string, result rules.FileLint, fixes bool, doc &vue.Document, sdoc &svelte.Document) FileReport {
	mut errors := strings.new_builder(0)
	if result.syntax_errors {
		errors.writeln('warning: ${path}: tree-sitter found syntax errors; results may be partial')
	}
	if result.unmatched > 0 {
		errors.writeln('warning: ${path}: ${result.unmatched} nodes not analyzed (tree-sitter and TypeScript read them differently, they are nested too deeply, or tsgo failed on them); some findings may be missing')
	}
	findings := result.findings
	if findings.len == 0 {
		return FileReport{
			stderr: errors.str()
		}
	}
	mut display := []offsets.DisplayPos{}
	// Where each report ends, for --fixes (an editor underlines the range).
	mut ends := []offsets.DisplayPos{}
	if doc != unsafe { nil } {
		display, ends = vue_report_positions(doc, findings, fixes)
	} else if sdoc != unsafe { nil } {
		display, ends = svelte_report_positions(sdoc, findings, fixes)
	} else {
		_, display = offsets.utf16_positions(src, findings.map(it.stmt))
		if fixes {
			_, ends = offsets.utf16_positions(src, findings.map(treesitter.Ident{
				start_byte: if it.stmt.end_byte >= 0 {
					it.stmt.end_byte
				} else {
					it.stmt.start_byte
				}
				row:        it.stmt.row
			}))
		}
		// A `loc` given as lines and columns (Finding.line_loc).
		for i, f in findings {
			if f.line_loc {
				display[i] = offsets.DisplayPos{
					line: f.fixed_line
					col:  f.fixed_column
				}
				if fixes {
					ends[i] = offsets.DisplayPos{
						line: f.fixed_end_line
						col:  f.fixed_end_column
					}
				}
			}
		}
	}
	mut out := strings.new_builder(findings.len * 200)
	mut warnings := 0
	for i, finding in findings {
		d := display[i]
		msg := tsv_field(rules.message(finding.rule, finding))
		// The rule as ESLint's ruleId names it: `@typescript-eslint/await-thenable`.
		col := if finding.column_from_zero { d.col - 1 } else { d.col }
		out.write_string('${path}:${d.line}:${col}\t${finding.rule}\t${finding.message_id}\t${msg}')
		if fixes {
			out.write_string(fix_fields(src, finding))
			if finding.no_end {
				// A `loc` of line 0 without an end (a selector error of vue/block-order).
			} else if finding.stmt.row < 0 {
				// A problem of the whole file (`loc` 0:0 to 0:0): ESLint ends it at 0:1 too.
				out.write_string('\tend\t0\t1')
			} else if finding.stmt.end_byte >= 0 {
				out.write_string('\tend\t${ends[i].line}\t${ends[i].col}')
			}
		}
		if finding.severity == 1 {
			// A warning ends with a field of its own, after everything else, so that the line of an
			// error stays as it was and a parser that stops at a field it does not know still reads
			// the rest. Fields are escaped and counted, so a message cannot fake it.
			out.write_string('\twarning')
			warnings++
		}
		out.writeln('')
	}
	return FileReport{
		stdout:   out.str()
		stderr:   errors.str()
		problems: findings.len
		warnings: warnings
	}
}

fn prepare_file(parser treesitter.Parser, path string, project_override string, all bool, mut bench BenchReport) !FileWork {
	mut sw := time.new_stopwatch()
	src, _, not_utf8 := read_source(path)!
	tree := parser.parse(src) or { return error('${path}: ${err.msg()}') }
	defer {
		treesitter.tree_delete(tree)
	}
	if treesitter.tree_has_error(tree) {
		eprintln('warning: ${path}: tree-sitter found syntax errors; results may be partial')
	}
	bench.read_parse_ms += ms(sw.elapsed())
	sw.restart()
	idents := parser.identifiers(tree, src, all)
	bench.query_ms += ms(sw.elapsed())
	sw.restart()
	utf16, display := offsets.utf16_positions(src, idents)
	bench.offsets_ms += ms(sw.elapsed())
	// Absolute path without resolving symlinks: tsgo knows the files by their project path.
	abs_path := os.abs_path(path)
	tsconfig := if project_override != '' { project_override } else { find_tsconfig(abs_path)! }
	bench.files++
	bench.identifiers += idents.len
	return FileWork{
		path:     path
		abs_path: abs_path
		ts_path:  abs_path
		tsconfig: tsconfig
		idents:   idents
		offsets:  utf16
		display:  display
		src:      if not_utf8 { src } else { '' }
		not_utf8: not_utf8
	}
}

// prepare_vue_file is prepare_file for a .vue file: the identifiers of its script, asked in its
// twin. A file whose script is JavaScript is skipped with a warning (its FileWork is not `vue`).
fn prepare_vue_file(mut vue_parsers VueParsers, parser treesitter.Parser, path string, project_override string, all bool, options vue.Options, mut bench BenchReport) !FileWork {
	mut sw := time.new_stopwatch()
	src, _, _ := read_source(path)!
	mut doc := vue_parsers.parse(src, options) or { return error('${path}: ${err.msg()}') }
	defer {
		doc.free()
	}
	if doc.script.lang == .js {
		eprintln(vue_javascript_warning(path))
		return FileWork{}
	}
	if doc.script.has_error {
		eprintln('warning: ${path}: tree-sitter found syntax errors; results may be partial')
	}
	bench.read_parse_ms += ms(sw.elapsed())
	sw.restart()
	idents, utf16, display := vue_identifiers(parser, doc, all)
	bench.query_ms += ms(sw.elapsed())
	abs_path := os.abs_path(path)
	tsconfig := if project_override != '' { project_override } else { find_tsconfig(abs_path)! }
	bench.files++
	bench.identifiers += idents.len
	return FileWork{
		path:      path
		abs_path:  abs_path
		ts_path:   rules.vue_twin_path(abs_path)
		tsconfig:  tsconfig
		idents:    idents
		offsets:   utf16
		display:   display
		vue:       true
		twin_code: doc.script.code
	}
}

// read_source reads a file as ESLint does: the text Node decodes from its bytes as UTF-8, with
// U+FFFD in the place of what is not (offsets.decode_utf8), and without the BOM. It also tells
// whether the file had a BOM and whether its bytes were not valid UTF-8; tsgo, which reads the
// files itself and counts those bytes in its own way, is then given this text.
fn read_source(path string) !(string, bool, bool) {
	raw := os.read_file(path) or { return error('cannot read ${path}: ${err.msg()}') }
	text, not_utf8 := offsets.decode_utf8(raw)
	src, has_bom := offsets.strip_bom(text)
	return src, has_bom, not_utf8
}

// find_tsconfig looks for the closest tsconfig.json going up from the file.
fn find_tsconfig(file string) !string {
	mut dir := os.dir(file)
	for {
		candidate := os.join_path(dir, 'tsconfig.json')
		if os.is_file(candidate) {
			return candidate
		}
		parent := os.dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return error('no tsconfig.json found for ${file}; pass one with --project')
}

// named_project ports how typescript-estree picks a program among the ones `parserOptions.project`
// names (getWatchProgramsForProjects): the first one whose root files have the file; none when no
// project of the snapshot has it.
fn named_project(snap tsgo.UpdateSnapshotResponse, named []string, abs_path string) ?string {
	file := tsgo.path_key(abs_path)
	for tsconfig in named {
		for p in snap.projects {
			if is_project_of(p, tsconfig) {
				if p.parsed_command_line.file_names.any(tsgo.path_key(it) == file) {
					return tsconfig
				}
				break
			}
		}
	}
	return none
}

// assign_named_projects gives the files whose configuration names projects the first one that has
// them or, where none does (typescript-eslint stops there with a parsing error), the closest
// tsconfig. Returns the tsconfig files that are not open in the snapshot yet.
fn assign_named_projects(mut files []RuleFile, snap tsgo.UpdateSnapshotResponse) ![]string {
	mut opened := []string{}
	for i, f in files {
		if f.named.len == 0 {
			continue
		}
		tsconfig := named_project(snap, f.named, f.ts_path) or { find_tsconfig(f.abs_path)! }
		if tsconfig !in f.named && tsconfig !in opened
			&& !snap.projects.any(is_project_of(it, tsconfig)) {
			opened << tsconfig
		}
		files[i] = RuleFile{
			...f
			tsconfig: tsconfig
		}
	}
	return opened
}

// no_snapshot is the snapshot of a run that has none yet (config_snapshot).
const no_snapshot = -1

// configs_need_types tells whether some rule of the configurations asks tsgo for types.
fn configs_need_types(configs []rules.LintConfig) bool {
	for config in configs {
		for setting in config.rules {
			if rules.needs_types(setting.name) {
				return true
			}
		}
	}
	return false
}

// config_snapshot stands for a snapshot when no rule needs types: `base` with the projects of
// `tsconfigs` added, each with its parsed tsconfig (parseConfigFile) and the tsconfig as its id,
// and no snapshot of tsgo, so no program is built.
fn config_snapshot(mut client tsgo.Client, base tsgo.UpdateSnapshotResponse, tsconfigs []string) !tsgo.UpdateSnapshotResponse {
	mut projects := base.projects.clone()
	for tsconfig in tsconfigs {
		projects << tsgo.ProjectResponse{
			id:                  tsconfig
			config_file_name:    tsconfig
			parsed_command_line: client.parse_config_file(tsconfig)!
		}
	}
	return tsgo.UpdateSnapshotResponse{
		snapshot: base.snapshot
		projects: projects
	}
}

// project_options are the compiler options of a project of the snapshot.
fn project_options(snap tsgo.UpdateSnapshotResponse, project string) tsgo.CompilerOptions {
	for p in snap.projects {
		if p.id == project {
			return p.compiler_options()
		}
	}
	return tsgo.CompilerOptions{}
}

// map_projects maps each tsconfig to the id of its project in the snapshot.
fn map_projects(tsconfigs []string, snap tsgo.UpdateSnapshotResponse) !map[string]string {
	mut result := map[string]string{}
	for cfg in tsconfigs {
		mut found := ''
		for p in snap.projects {
			if is_project_of(p, cfg) {
				found = p.id
				break
			}
		}
		if found == '' {
			return error('tsconfig ${cfg} is not in the tsgo snapshot (projects: ${snap.projects.map(it.id)})')
		}
		result[cfg] = found
	}
	return result
}

// is_project_of tells whether a project of the snapshot is the one of a tsconfig.
fn is_project_of(p tsgo.ProjectResponse, tsconfig string) bool {
	key := tsgo.path_key(tsconfig)
	return tsgo.path_key(p.id) == key || tsgo.path_key(p.config_file_name) == key
}

// query_file asks for the symbols and types of every identifier of a file: one request of each
// kind per file or, with --per-identifier, one per identifier.
fn query_file(mut client tsgo.Client, snapshot int, project string, w FileWork, per_identifier bool, mut bench BenchReport) !([]tsgo.SymbolResponse, []tsgo.TypeResponse) {
	if !per_identifier {
		mut sw := time.new_stopwatch()
		symbols := client.symbols_at(snapshot, project, w.ts_path, w.offsets)!
		symbols_elapsed := ms(sw.elapsed())
		bench.add_symbols(symbols_elapsed)
		bench.symbol_batches_ms << symbols_elapsed
		sw.restart()
		types := client.types_at(snapshot, project, w.ts_path, w.offsets)!
		types_elapsed := ms(sw.elapsed())
		bench.add_types(types_elapsed)
		bench.type_batches_ms << types_elapsed
		if symbols.len != w.offsets.len || types.len != w.offsets.len {
			return error('protocol: tsgo returned ${symbols.len} symbols and ${types.len} types for ${w.offsets.len} positions')
		}
		return symbols, types
	}
	mut symbols := []tsgo.SymbolResponse{cap: w.offsets.len}
	mut types := []tsgo.TypeResponse{cap: w.offsets.len}
	for pos in w.offsets {
		mut sw := time.new_stopwatch()
		symbols << client.symbol_at(snapshot, project, w.ts_path, pos)!
		bench.add_symbols(ms(sw.elapsed()))
		sw.restart()
		types << client.type_at(snapshot, project, w.ts_path, pos)!
		bench.add_types(ms(sw.elapsed()))
	}
	return symbols, types
}

// fix_fields are the extra fields of a finding with --fixes: `<TAB>fix<TAB>start<TAB>end<TAB>text`
// for its fix and `<TAB>suggestion<TAB>messageId<TAB>message<TAB>start<TAB>end<TAB>text` for each
// suggestion, with the ranges in UTF-16 units like ESLint's.
fn fix_fields(src string, finding rules.Finding) string {
	mut byte_offsets := []int{}
	if finding.has_fix {
		byte_offsets << [finding.fix.start, finding.fix.end]
	}
	for s in finding.suggestions {
		byte_offsets << [s.fix.start, s.fix.end]
	}
	if byte_offsets.len == 0 {
		return ''
	}
	// The range [-1, 0] is the BOM, before the text (unicode-bom): it stays -1.
	mut units := offsets.utf16_offsets(src, byte_offsets.map(if it < 0 { 0 } else { it }))
	for i, offset in byte_offsets {
		if offset < 0 {
			units[i] = offset
		} else if offset > src.len {
			// A range past the end of the text (ban-tslint-comment removes one more unit after a
			// comment at the end): ESLint prints it as it is.
			units[i] += offset - src.len
		}
	}
	mut out := strings.new_builder(200)
	mut next := 0
	if finding.has_fix {
		out.write_string('\tfix\t${units[0]}\t${units[1]}\t${tsv_field(finding.fix.text)}')
		next = 2
	}
	for s in finding.suggestions {
		desc := tsv_field(rules.suggestion_message(finding.rule, s))
		out.write_string('\tsuggestion\t${s.message_id}\t${desc}\t${units[next]}\t${units[next + 1]}\t${tsv_field(s.fix.text)}')
		next += 2
	}
	return out.str()
}

// note_line is the line of ESLint's warning about a file it does not lint (`File ignored because of
// a matching ignore pattern…`): a problem of the whole file, of severity 1 as in ESLint, so it ends
// with the field `warning` like every warning.
fn note_line(path string, note string) string {
	return '${path}:0:0\t${rules.problem_rule}\twarning\t${tsv_field(note)}\twarning'
}

// tsv_field escapes a field of an output line: the message may carry source text (`[a,⏎ b]` in
// no-unsafe-member-access), and a newline or a tab would break the format.
fn tsv_field(s string) string {
	return s.replace_each(['\\', '\\\\', '\n', '\\n', '\r', '\\r', '\t', '\\t'])
}

// check_invariant checks that, at each position, tsgo resolved a symbol with the same name as the
// identifier tree-sitter saw (PROMPT.md §4, step 8).
fn check_invariant(w FileWork, symbols []tsgo.SymbolResponse, all_identifiers bool) ! {
	for i, id in w.idents {
		sym := symbols[i]
		d := w.display[i]
		where := '${w.path}:${d.line}:${d.col}'
		if sym.is_null() {
			if all_identifiers {
				continue
			}
			return error('position mismatch in ${where}: tsgo found no symbol for `${id.text}` (byte ${id.start_byte}, UTF-16 ${w.offsets[i]})')
		}
		name := unescape_leading_underscores(sym.name)
		if name != id.text && !invariant_exempt(id.text, name) {
			return error('position mismatch in ${where}: tree-sitter saw `${id.text}` (byte ${id.start_byte}, UTF-16 ${w.offsets[i]}) and tsgo resolved the symbol `${name}`')
		}
	}
}

// unescape_leading_underscores undoes the escaping TypeScript applies to symbol names: an
// identifier starting with `__` is stored with one more `_` (`__x` → `___x`).
fn unescape_leading_underscores(name string) string {
	if name.starts_with('___') {
		return name[1..]
	}
	return name
}

// invariant_exempt covers the two cases where tsgo legitimately gives another name (checked with
// 7.0.2): `export default function foo` resolves to the `default` symbol, and an identifier
// written with escapes (`abc`) resolves to its decoded name.
fn invariant_exempt(text string, symbol_name string) bool {
	return symbol_name == 'default' || text.contains('\\')
}

// TypeCache keeps typeToString and the base type by id. Ids are unique per (snapshot, project), so
// the key includes the project.
struct TypeCache {
mut:
	names map[string]string
	bases map[string]int
}

fn cache_key(project string, type_id int) string {
	return '${project}#${type_id}'
}

fn (mut tc TypeCache) name(mut client tsgo.Client, snapshot int, project string, type_id int, mut bench BenchReport) !string {
	key := cache_key(project, type_id)
	if key in tc.names {
		bench.type_cache_hits++
		return tc.names[key]
	}
	name := client.type_to_string(snapshot, project, type_id)!
	bench.type_to_string_requests++
	tc.names[key] = name
	return name
}

fn (mut tc TypeCache) base(mut client tsgo.Client, snapshot int, project string, type_id int, mut bench BenchReport) !int {
	key := cache_key(project, type_id)
	if key in tc.bases {
		bench.type_cache_hits++
		return tc.bases[key]
	}
	base := client.base_type_of_literal(snapshot, project, type_id)!
	bench.base_type_requests++
	tc.bases[key] = base.id
	return base.id
}

// describe returns the text of the type and, for a literal, its base type too.
fn (mut tc TypeCache) describe(mut client tsgo.Client, snapshot int, project string, t tsgo.TypeResponse, mut bench BenchReport) !string {
	if t.is_null() {
		return '<no type>'
	}
	name := tc.name(mut client, snapshot, project, t.id, mut bench)!
	base_id := tc.base(mut client, snapshot, project, t.id, mut bench)!
	if base_id == 0 || base_id == t.id {
		return name
	}
	base_name := tc.name(mut client, snapshot, project, base_id, mut bench)!
	return '${name}\t(base: ${base_name})'
}
