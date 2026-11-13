module main

import json2
import offsets
import os
import rules
import strings
import time
import treesitter
import tsgo

// veslint: parses TypeScript with tree-sitter and asks tsgo (`tsc --api`) for the types.
// Flow from PROMPT.md §4.

const usage = 'usage: veslint <file.ts>... [--project <tsconfig.json>] [--all-identifiers] [--bench] [--per-identifier] [--rule <rule> | --config <eslint.config.mjs | rules.json> [--print-config]] [--fix] [--fixes] | veslint --server'
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
	fixes           bool         // --fixes: print the fix and the suggestions of each finding
	fix             bool         // --fix: apply the fixes and write the files, like `eslint --fix`
	print_config    bool         // --print-config: print the resolved configuration and exit
	server          bool         // --server: lint the requests of an editor until stdin ends (server.v)
	rules           []RuleConfig // the rules of --rule or of every configuration of --config
	ignored         []string     // active rules from --config that veslint does not have
	loaded          LoadedConfig // the configuration of each file (--rule: a single one)
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
			'--server' {
				opts.server = true
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
				if treesitter.is_javascript_path(arg) {
					return error('${arg}: veslint only reads TypeScript (.ts, .mts, .cts, .tsx)')
				}
				opts.files << arg
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
	if opts.files.len == 0 {
		return error('missing file to analyze')
	}
	if rule != '' && config != '' {
		return error('--rule and --config cannot be combined')
	}
	if (rule != '' || config != '') && (opts.all_identifiers || opts.per_identifier) {
		return error('--all-identifiers and --per-identifier belong to type mode; they cannot be combined with --rule or --config')
	}
	if rule != '' {
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
				setup: RuleSetup{
					rules:        opts.rules
					base_options: {
						rule: rules.decoded_default_options(rule)
					}
				}
			}]
			file_config: file_config
		}
	}
	if opts.print_config && config == '' {
		return error('--print-config needs --config with an ESLint configuration file')
	}
	if config != '' {
		opts.loaded = load_config_for(config, opts.files)!
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
	return opts
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
	for path in opts.files {
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
	for w in works {
		if w.not_utf8 {
			served[w.abs_path] = w.src
		}
	}
	mut client := tsgo.start_with_files(tsgo.binary_path(), os.dir(tsconfigs[0]), timeout,
		served)!
	defer {
		client.shutdown()
	}
	_ = client.initialize()!
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
}

// run_rules applies the rules to the files and prints one line per problem:
// `path:line:col<TAB>rule<TAB>messageId<TAB>message`. Returns how many errors there were (findings
// of rules set to "warn" do not count).
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
			path:     path
			abs_path: abs_path
			tsconfig: tsconfig
			named:    named
			src:      src
			has_bom:  has_bom
			not_utf8: not_utf8
		}
	}
	bench.files = files.len
	if tsconfigs.len == 0 {
		// ESLint lints none of the files: only its message for each one.
		for f in files {
			println('${f.path}:0:0\t${rules.problem_rule}\twarning\t${tsv_field(f.note)}')
		}
		eprintln('${files.len} problems in ${files.len} files (${files.len} of them warnings)')
		return 0
	}
	mut sw := time.new_stopwatch()
	mut served := map[string]string{}
	for f in files {
		if f.not_utf8 {
			served[f.abs_path] = f.src
		}
	}
	mut client := tsgo.start_with_files(tsgo.binary_path(), os.dir(tsconfigs[0]), timeout,
		served)!
	defer {
		client.shutdown()
	}
	_ = client.initialize()!
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
	mut problems := 0
	mut warnings := 0
	mut fixed_files := 0
	mut stats := rules.Stats{}
	for f in files {
		if f.note != '' {
			println('${f.path}:0:0\t${rules.problem_rule}\twarning\t${tsv_field(f.note)}')
			problems++
			warnings++
			continue
		}
		lint_config := lint_configs[opts.loaded.file_config[f.abs_path] or { 0 }]
		mut src := f.src
		mut has_bom := f.has_bom
		mut result := rules.FileLint{}
		// --fix ports ESLint's verifyAndFix: lint, apply the fixes that do not overlap, and lint the
		// result again, up to 10 passes or until two passes give the same text. tsgo only reads
		// files, so each pass is written to disk and a new snapshot is taken.
		mut pass := 0
		mut previous := ''
		mut second_previous := ''
		for {
			pass++
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
			result = checker.lint_file(if treesitter.uses_jsx_dialect(f.path) {
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
			// What is on disk now is valid UTF-8: tsgo reads it from there.
			client.stop_serving(f.abs_path)
			if pass == 1 {
				fixed_files++
			}
			previous_snapshot := snap.snapshot
			snap = client.update_snapshot_changed(snap, [f.abs_path])!
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
		report := file_report(f.path, src, result, opts.fixes)
		eprint(report.stderr)
		print(report.stdout)
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
fn file_report(path string, src string, result rules.FileLint, fixes bool) FileReport {
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
	_, display := offsets.utf16_positions(src, findings.map(it.stmt))
	mut out := strings.new_builder(findings.len * 200)
	mut warnings := 0
	for i, finding in findings {
		d := display[i]
		msg := tsv_field(rules.message(finding.rule, finding))
		// The rule as ESLint's ruleId names it: `@typescript-eslint/await-thenable`.
		out.write_string('${path}:${d.line}:${d.col}\t${finding.rule}\t${finding.message_id}\t${msg}')
		if fixes {
			out.write_string(fix_fields(src, finding))
		}
		out.writeln('')
		if finding.severity == 1 {
			warnings++
		}
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
		tsconfig: tsconfig
		idents:   idents
		offsets:  utf16
		display:  display
		src:      if not_utf8 { src } else { '' }
		not_utf8: not_utf8
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
		tsconfig := named_project(snap, f.named, f.abs_path) or { find_tsconfig(f.abs_path)! }
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
		symbols := client.symbols_at(snapshot, project, w.abs_path, w.offsets)!
		symbols_elapsed := ms(sw.elapsed())
		bench.add_symbols(symbols_elapsed)
		bench.symbol_batches_ms << symbols_elapsed
		sw.restart()
		types := client.types_at(snapshot, project, w.abs_path, w.offsets)!
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
		symbols << client.symbol_at(snapshot, project, w.abs_path, pos)!
		bench.add_symbols(ms(sw.elapsed()))
		sw.restart()
		types << client.type_at(snapshot, project, w.abs_path, pos)!
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
