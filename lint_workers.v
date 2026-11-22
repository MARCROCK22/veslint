module main

import offsets
import os
import rules
import svelte
import sync
import time
import treesitter
import tsgo
import vue

// A lint runs its files on workers, threads with tree-sitter parsers and rule checkers of their
// own. With TypeScript in this process (the archive of tsgo/inproc), the workers share one
// session: it is opened and its snapshot taken once (SharedSession), so every program is built
// once, and each worker asks with a client of its own (Client.worker_client), whose checker
// requests the session answers with a checker of the worker's (as tsgolint's workers have one
// each), so that they do not wait for each other. Otherwise (a `tsc --api` process; no rule that
// needs types, where a checker may make a snapshot of its own; --fix, which writes files and
// takes new snapshots) each worker opens its own session and builds the same snapshot with the
// same requests. A worker takes the next file not taken yet and keeps its reports; they are
// printed in the order of the files, as a single worker prints them. What a file gives does not
// depend on the worker: TypeScript 7 orders types (union members, for instance) by a stable order
// instead of the order a checker made them in, and the rules' Checker caches only what does not
// depend on the files linted before.

// min_files_per_worker: a worker checks again what the others checked (each checker resolves
// the types it needs, those of the globals and libraries too), which a few files do not pay back.
const min_files_per_worker = 8

// LintPlan is what the workers of a lint share; none of them changes it.
@[heap]
struct LintPlan {
	loaded       &LoadedConfig = unsafe { nil }
	lint_configs []rules.LintConfig
	fix          bool
	fixes        bool
	timeout      time.Duration
	// The tsconfigs of the files, before the snapshot gives those of `parserOptions.project`.
	tsconfigs []string
	served    map[string]string
	virtual   map[string]string
	// No rule needs types: the checkers make a snapshot only if a file asks for one.
	lazy bool
}

// FileOutcome is what linting a file gave: its report, its findings (for --summary) and the
// warnings of --fix, which are printed before the report.
struct FileOutcome {
	report   FileReport
	findings []rules.Finding
	warnings string
}

// Worker lints files with its own TypeScript session, tree-sitter parsers and rule checkers.
@[heap]
struct Worker {
mut:
	client          &tsgo.Client = unsafe { nil }
	snap            tsgo.UpdateSnapshotResponse
	files           []RuleFile // with the tsconfig of `parserOptions.project` (assign_named_projects)
	tsconfigs       []string
	projects        map[string]string // tsconfig -> project of the snapshot
	checkers        map[string]&rules.Checker
	last_of_project map[string]int
	parser          treesitter.Parser
	tsx_parser      treesitter.Parser // .tsx files use the grammar's tsx dialect
	vue_parsers     VueParsers
	svelte_parsers  SvelteParsers
	stats           rules.Stats
	fixed_files     int
	start_ms        f64 // starting TypeScript, until the first snapshot is asked for
	snapshot_ms     f64
}

// SharedSession is the TypeScript session the workers of a lint share, with its snapshot; the
// worker that opened it (`owner`) lints no file and closes it after the others are done.
@[heap]
struct SharedSession {
mut:
	owner &Worker = unsafe { nil }
}

// open_shared starts TypeScript in this process and takes the snapshot of the lint, for workers
// that share them (worker_of).
fn open_shared(plan &LintPlan, files []RuleFile) !&SharedSession {
	return &SharedSession{
		owner: open_worker(plan, files)!
	}
}

// worker_of is the worker `number` (1 or more) of a shared session: the snapshot, projects and
// files of the owner, and a client of its own.
fn (s &SharedSession) worker_of(plan &LintPlan, number int) !&Worker {
	owner := s.owner
	mut w := &Worker{
		client:      owner.client.worker_client(number)!
		snap:        owner.snap
		files:       owner.files.clone()
		tsconfigs:   owner.tsconfigs.clone()
		projects:    owner.projects.clone()
		parser:      treesitter.new_parser()!
		tsx_parser:  treesitter.new_tsx_parser()!
		start_ms:    owner.start_ms
		snapshot_ms: owner.snapshot_ms
	}
	w.mark_last_files(plan)
	return w
}

fn (mut s SharedSession) close() {
	if s.owner != unsafe { nil } {
		s.owner.close()
	}
}

// open_worker starts TypeScript and takes the snapshot of the lint.
fn open_worker(plan &LintPlan, files []RuleFile) !&Worker {
	mut w := &Worker{
		files:      files.clone()
		tsconfigs:  plan.tsconfigs.clone()
		parser:     treesitter.new_parser()!
		tsx_parser: treesitter.new_tsx_parser()!
	}
	w.open(plan) or {
		w.close()
		return err
	}
	return w
}

fn (mut w Worker) open(plan &LintPlan) ! {
	mut sw := time.new_stopwatch()
	cwd := os.dir(w.tsconfigs[0])
	w.client = if plan.virtual.len > 0 {
		tsgo.start_virtual(tsgo.binary_path(), cwd, plan.timeout, plan.served, plan.virtual)!
	} else {
		tsgo.start_with_files(tsgo.binary_path(), cwd, plan.timeout, plan.served)!
	}
	_ = w.client.initialize()!
	if plan.virtual.len > 0 {
		mut twins := map[string][]string{}
		for f in w.files {
			if (f.vue || f.svelte) && f.tsconfig != '' {
				twins[f.tsconfig] << f.ts_path
			}
		}
		include_twins(mut w.client, twins)!
	}
	w.start_ms = ms(sw.elapsed())
	sw.restart()
	// When no rule of the configurations needs types, tsgo only parses the tsconfigs and builds no
	// program: a checker makes a snapshot if a comment turns on a rule that needs them, or if an
	// `await` may be a name (Checker.make_snapshot). --fix keeps the snapshot of every pass, as
	// tsgo has to be told of each file it writes.
	mut snap := if plan.lazy {
		config_snapshot(mut w.client, tsgo.UpdateSnapshotResponse{ snapshot: no_snapshot },
			w.tsconfigs)!
	} else {
		w.client.create_snapshot(w.tsconfigs)!
	}
	opened := assign_named_projects(mut w.files, snap)!
	if opened.len > 0 {
		if plan.lazy {
			snap = config_snapshot(mut w.client, snap, opened)!
		} else {
			previous_snapshot := snap.snapshot
			snap = w.client.update_snapshot_files(snap, opened, tsgo.FileChangeSet{})!
			if snap.snapshot != previous_snapshot {
				w.client.release_snapshot(previous_snapshot)!
			}
		}
		w.tsconfigs << opened
	}
	w.snap = snap
	w.snapshot_ms = ms(sw.elapsed())
	w.projects = map_projects(w.tsconfigs, snap)!
	w.mark_last_files(plan)
}

// mark_last_files finds the index of the last file of each project: without --fix (whose passes
// make new snapshots and checkers), the checker of a project is dropped after it, so that a run
// over files of many tsconfigs does not keep every checker alive (the garbage collector walks what
// is alive).
fn (mut w Worker) mark_last_files(plan &LintPlan) {
	if !plan.fix {
		for index, f in w.files {
			if f.note == '' {
				w.last_of_project[w.projects[f.tsconfig]] = index
			}
		}
	}
}

fn (mut w Worker) close() {
	if w.client != unsafe { nil } {
		w.client.shutdown()
	}
	w.parser.close()
	w.tsx_parser.close()
	w.vue_parsers.close()
	w.svelte_parsers.close()
}

// lint lints the file `index` (not a file with a note): with --fix, until its fixes are applied.
fn (mut w Worker) lint(plan &LintPlan, index int) !FileOutcome {
	f := w.files[index]
	config_index := plan.loaded.file_config[f.abs_path] or { 0 }
	mut lint_config := plan.lint_configs[config_index]
	if f.abs_path in plan.loaded.file_runes {
		// A runes function of the svelteConfig: what it gave for this file (file_language).
		lint_config = rules.LintConfig{
			...lint_config
			language: plan.loaded.file_language(f.abs_path, lint_config.language)
		}
	}
	// In a single run, the project service leaves the file to a Program made for its tsconfig,
	// whose current directory is the one ESLint runs in, when the tsconfig is the one veslint
	// lints the file with; only for the text on disk (the first pass of --fix).
	service_directory := lint_config.program_directory
	if config_index < plan.loaded.configs.len && is_single_run(plan.fix) {
		root := plan.loaded.configs[config_index].service_program_root
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
		doc = w.vue_parsers.parse(src, f.vue_options) or { return error('${f.path}: ${err.msg()}') }
	}
	// The document of a .svelte file, the same way.
	mut sdoc := &svelte.Document(unsafe { nil })
	if f.svelte {
		sdoc = w.svelte_parsers.parse(src, f.svelte_options) or {
			return error('${f.path}: ${err.msg()}')
		}
	}
	// --fix ports ESLint's verifyAndFix: lint, apply the fixes that do not overlap, and lint the
	// result again, up to 10 passes or until two passes give the same text. tsgo only reads
	// files, so each pass is written to disk and a new snapshot is taken.
	mut pass := 0
	mut syntax_baseline := -1
	mut previous := ''
	mut second_previous := ''
	mut warnings := ''
	for {
		pass++
		if pass > 1 {
			lint_config.program_directory = service_directory
		}
		project := w.projects[f.tsconfig]
		if project !in w.checkers {
			mut new_checker := rules.new_checker(w.client, w.snap.snapshot, project, project_options(w.snap,
				project))!
			new_checker.set_project_directory(os.dir(f.tsconfig))
			if plan.lazy {
				new_checker.defer_snapshot(project)
			}
			w.checkers[project] = new_checker
		}
		mut checker := w.checkers[project] or { return error('no checker for ${project}') }
		checker.set_has_bom(has_bom)
		// A fix may give code TypeScript cannot parse: from the second pass on, a parsing error
		// that was not in the file is reported alone and stops the fixes, as ESLint does.
		if plan.fix {
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
			checker.set_svelte(sdoc, f.ts_path, w.svelte_parsers.parsers)
		} else if module.inserted > 0 {
			checker.set_svelte_module(src, module.code, module.at, module.inserted)
		}
		result = checker.lint_file(if (f.vue && doc.script.jsx) || (f.svelte && sdoc.options.jsx)
			|| (!f.vue && !f.svelte && treesitter.uses_jsx_dialect(f.path)) {
			w.tsx_parser
		} else {
			w.parser
		},
			lint_config, src, f.abs_path, mut w.stats) or {
			return error('${f.path}: ${err.msg()}')
		}
		if !plan.fix || pass > max_fix_passes {
			break
		}
		// ESLint does not fix a file it cannot parse (a fix of the previous pass may have broken it).
		if result.parsing_error {
			break
		}
		if result.syntax_errors {
			if result.findings.any(it.has_fix) {
				warnings += 'warning: ${f.path}: not fixed, because tree-sitter found syntax errors\n'
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
			doc = w.vue_parsers.parse(src, f.vue_options) or {
				return error('${f.path}: ${err.msg()}')
			}
			w.client.serve(f.ts_path, doc.script.code)
		} else if f.svelte {
			sdoc.free()
			sdoc = w.svelte_parsers.parse(src, f.svelte_options) or {
				return error('${f.path}: ${err.msg()}')
			}
			w.client.serve(f.ts_path, sdoc.virtual_code)
		} else if f.module.inserted > 0 || module.inserted > 0 {
			// The module's virtual code is made again from the fixed text.
			module = w.svelte_parsers.module_virtual(src) or {
				return error('${f.path}: ${err.msg()}')
			}
			w.client.serve(f.abs_path, module.code)
		} else {
			// What is on disk now is valid UTF-8: tsgo reads it from there.
			w.client.stop_serving(f.abs_path)
		}
		if pass == 1 {
			w.fixed_files++
		}
		previous_snapshot := w.snap.snapshot
		w.snap = w.client.update_snapshot_changed(w.snap, [f.ts_path])!
		w.projects = map_projects(w.tsconfigs, w.snap)!
		w.checkers.clear()
		if w.snap.snapshot != previous_snapshot {
			w.client.release_snapshot(previous_snapshot)!
		}
		if pass > 1 && src == second_previous {
			warnings += 'warning: ${f.path}: circular fixes; stopped after ${pass} passes\n'
			pass = max_fix_passes
		}
	}
	if !plan.fix {
		// This worker takes no file before this one from now on: the checkers of the projects
		// whose files are all taken are not needed any more.
		for project in w.checkers.keys() {
			if w.last_of_project[project] <= index {
				w.checkers.delete(project)
			}
		}
	}
	report := file_report(f.path, src, result, plan.fixes, doc, sdoc)
	if f.vue {
		doc.free()
	}
	if f.svelte {
		sdoc.free()
	}
	return FileOutcome{
		report:   report
		findings: result.findings
		warnings: warnings
	}
}

// FileQueue hands the files to the workers. Each worker starts with a run of consecutive files of
// its own (split), the files of a few directories, which use the same types: a checker of its own
// resolves the types of those files, and the types the files of a directory share are resolved by
// one checker instead of every worker's. A worker done with its run takes the last file of the run
// with the most files left.
@[heap]
struct FileQueue {
mut:
	mutex &sync.Mutex = sync.new_mutex()
	files []RuleFile
	// The run of each worker: files[starts[w]..ends[w]] are left (worker numbers start at 1; 0 is
	// the only worker of a lint without others).
	starts []int
	ends   []int
	stop   bool
}

// split gives each of `count` workers a run of the files with about as many bytes of source; 0
// gives them all to the only worker, 0.
fn (mut q FileQueue) split(count int) {
	if count == 0 {
		q.starts = [0]
		q.ends = [q.files.len]
		return
	}
	mut total := u64(0)
	for f in q.files {
		total += u64(f.src.len)
	}
	q.starts = []int{len: count + 1}
	q.ends = []int{len: count + 1}
	mut at := 0
	mut sum := u64(0)
	for w in 1 .. count + 1 {
		q.starts[w] = at
		// The run ends where the bytes so far reach this worker's share of the total.
		for at < q.files.len && (w == count || sum * u64(count) < total * u64(w)) {
			sum += u64(q.files[at].src.len)
			at++
		}
		q.ends[w] = at
	}
}

// take is the index of the next file `worker` lints, or -1 when there is none or a worker failed.
fn (mut q FileQueue) take(worker int) int {
	q.mutex.lock()
	defer {
		q.mutex.unlock()
	}
	for !q.stop {
		mut index := -1
		if q.starts[worker] < q.ends[worker] {
			index = q.starts[worker]
			q.starts[worker]++
		} else {
			mut most := -1
			for w in 0 .. q.starts.len {
				if q.ends[w] - q.starts[w] > 0
					&& (most < 0 || q.ends[w] - q.starts[w] > q.ends[most] - q.starts[most]) {
					most = w
				}
			}
			if most < 0 {
				return -1
			}
			q.ends[most]--
			index = q.ends[most]
		}
		if q.files[index].note == '' {
			return index
		}
	}
	return -1
}

fn (mut q FileQueue) halt() {
	q.mutex.lock()
	q.stop = true
	q.mutex.unlock()
}

// WorkerResult is what a worker did.
struct WorkerResult {
mut:
	outcomes map[int]FileOutcome
	// failed: the file `failed_at` failed with `error` (-1: TypeScript did not start).
	failed      bool
	failed_at   int
	error       string
	stats       rules.Stats
	requests    int
	methods     map[string]tsgo.MethodStat
	tsgo_ms     f64
	fixed_files int
	start_ms    f64
	snapshot_ms f64
	// VESLINT_TIMELINE: when each file was linted and the time of TypeScript in it.
	timeline []TimelineEntry
}

// TimelineEntry is a file a worker linted (VESLINT_TIMELINE): monotonic start and end in
// nanoseconds, and the milliseconds of TypeScript's requests in between.
struct TimelineEntry {
	index    int
	start_ns u64
	end_ns   u64
	tsgo_ms  f64
}

// run_worker opens a worker (the worker `number` of `shared`, when there is one) and lints the
// files the queue gives it.
fn run_worker(plan &LintPlan, queue &FileQueue, shared &SharedSession, number int) WorkerResult {
	mut q := unsafe { queue }
	mut out := WorkerResult{}
	mut w := if shared != unsafe { nil } {
		shared.worker_of(plan, number) or {
			q.halt()
			out.failed = true
			out.failed_at = -1
			out.error = err.msg()
			return out
		}
	} else {
		open_worker(plan, q.files) or {
			q.halt()
			out.failed = true
			out.failed_at = -1
			out.error = err.msg()
			return out
		}
	}
	defer {
		w.close()
	}
	timeline := os.getenv('VESLINT_TIMELINE') != ''
	for {
		index := q.take(number)
		if index < 0 {
			break
		}
		t0 := time.sys_mono_now()
		g0 := w.client.inproc_ms()
		outcome := w.lint(plan, index) or {
			q.halt()
			out.failed = true
			out.failed_at = index
			out.error = err.msg()
			break
		}
		out.outcomes[index] = outcome
		if timeline {
			out.timeline << TimelineEntry{index, t0, time.sys_mono_now(), w.client.inproc_ms() - g0}
		}
	}
	out.stats = w.stats
	out.requests = w.client.request_count()
	out.methods = w.client.method_stats().clone()
	out.tsgo_ms = w.client.inproc_ms()
	out.fixed_files = w.fixed_files
	out.start_ms = w.start_ms
	out.snapshot_ms = w.snapshot_ms
	return out
}

// lint_files lints the files on `count` workers (one with --fix, which writes the files and takes
// a new snapshot after each pass, which the other workers' sessions would not have).
fn lint_files(plan &LintPlan, files []RuleFile, count int) []WorkerResult {
	mut queue := &FileQueue{
		files: files
	}
	no_session := &SharedSession(unsafe { nil })
	if count <= 1 {
		queue.split(0)
		results := [run_worker(plan, queue, no_session, 0)]
		write_timeline(results, files)
		return results
	}
	queue.split(count)
	mut shared := no_session
	if shares_session(plan) {
		shared = open_shared(plan, files) or {
			return [WorkerResult{
				failed:    true
				failed_at: -1
				error:     err.msg()
			}]
		}
	}
	mut threads := []thread WorkerResult{cap: count}
	for number in 1 .. count + 1 {
		threads << spawn run_worker(plan, queue, shared, number)
	}
	mut results := threads.wait()
	write_timeline(results, files)
	if shared != unsafe { nil } {
		// The owner's requests (the snapshot) count with the first worker's.
		results[0].requests += shared.owner.client.request_count()
		merge_methods(mut results[0].methods, shared.owner.client.method_stats())
		results[0].tsgo_ms += shared.owner.client.inproc_ms()
		mut s := unsafe { shared }
		s.close()
	}
	return results
}

// write_timeline writes the files each worker linted to the file VESLINT_TIMELINE names: a line
// per file, `worker start_ms end_ms tsgo_ms bytes path`, the times from the first start.
fn write_timeline(results []WorkerResult, files []RuleFile) {
	path := os.getenv('VESLINT_TIMELINE')
	if path == '' {
		return
	}
	mut first := u64(0)
	for r in results {
		for e in r.timeline {
			if first == 0 || e.start_ns < first {
				first = e.start_ns
			}
		}
	}
	mut lines := []string{}
	for worker, r in results {
		for e in r.timeline {
			lines << '${worker + 1} ${f64(e.start_ns - first) / 1e6:.1f} ${f64(e.end_ns - first) / 1e6:.1f} ${e.tsgo_ms:.1f} ${files[e.index].src.len} ${files[e.index].path}'
		}
	}
	os.write_file(path, lines.join_lines() + '\n') or {}
}

// shares_session tells whether the workers of a lint share one TypeScript session (see the top of
// this file): TypeScript in this process, a rule that needs types, and no --fix.
fn shares_session(plan &LintPlan) bool {
	transport := tsgo.transport_from_env() or { return false }
	return transport == .inproc && !plan.lazy && !plan.fix
}

// worker_count is how many workers lint `lintable` files on `cpus` CPUs.
fn worker_count(fix bool, lintable int, cpus int) int {
	if fix {
		return 1
	}
	return int_max(1, int_min(cpus, lintable / min_files_per_worker))
}

// merge_methods adds the requests of each method of a client to `into`.
fn merge_methods(mut into map[string]tsgo.MethodStat, from map[string]tsgo.MethodStat) {
	for method, stat in from {
		mut sum := into[method] or { tsgo.MethodStat{} }
		sum.count += stat.count
		sum.time += stat.time
		into[method] = sum
	}
}

// merge_stats adds the statistics of a worker to `into` (for --bench, whose times are then the
// sum of the workers').
fn merge_stats(mut into rules.Stats, s rules.Stats) {
	into.parse_ms += s.parse_ms
	into.parse_tree_sitter_ms += s.parse_tree_sitter_ms
	into.parse_index_ms += s.parse_index_ms
	into.parse_syntax_ms += s.parse_syntax_ms
	into.parse_await_ms += s.parse_await_ms
	into.tree_free_ms += s.tree_free_ms
	into.nodes += s.nodes
	into.types_ms += s.types_ms
	into.eval_ms += s.eval_ms
	into.checked += s.checked
	into.unmatched += s.unmatched
	into.findings += s.findings
	for rule, t in s.rule_ms {
		into.rule_ms[rule] += t
	}
}
