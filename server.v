module main

import json2
import offsets
import os
import strings
import time
import rules
import treesitter
import tsgo

// veslint --server: a process that stays alive between the requests of an editor, so that tsgo,
// the project it has open and the tree-sitter parsers are not started again for every save.
//
// It reads one JSON request per line on stdin and writes one JSON answer per line on stdout, in
// order, until stdin ends. A request:
//
//   {"id": 1, "config": "eslint.config.json", "project": "", "files": ["/abs/a.ts"],
//    "texts": {"/abs/a.ts": "unsaved text"}, "fixes": true,
//    "changed": ["/abs/b.ts"], "created": [], "deleted": [], "forget": [], "reset": false}
//
// - `files` are linted with `config`, as `veslint --config <config> [--fixes] <files>` would lint
//   them, in the directory the server runs in; `project` is `--project`.
// - `texts` has the text of files that are not saved, whether the request lints them or not: tsgo
//   is given that text instead of the file on disk (its readFile callback), for those files and
//   for the files that import them, until a later request lints the file without its text or
//   names it in `forget`.
// - `changed`, `created` and `deleted` are the files that changed on disk since the last request,
//   so that tsgo reads them again; `reset` makes it forget every file it read (a tsconfig.json or a
//   package changed).
// - A request without files only records those changes.
//
// The answer has the request's `id`, and `stdout`, `stderr` and `code`: exactly what that run of
// the command line would print on each stream and its exit code, so a client reads it as it would
// read the command line; only the usage text that follows the command line's errors in what it is
// given (code 2) is left out.
//
// A client may send a request before the answer to the previous one: a thread reads them as they
// come. A request whose files a later request lints too (an editor sends one for each change of a
// file) is given up, before it starts or between two rules, and answered
// {"id": 1, "code": 0, "stdout": "", "stderr": "", "cancelled": true}; its changes and texts count
// all the same.

// ServerAnswer is the answer to a request.
struct ServerAnswer {
	id        i64
	code      int
	stdout    string
	stderr    string
	cancelled bool @[omitempty] // given up for a later request with the same files
}

// ServerRequest is a line of stdin as the reader thread parsed it.
struct ServerRequest {
	request map[string]json2.Any
	files   string // the files it lints, joined: a later request with the same ones supersedes it
	error   string // the error answered (code 2) to a line that is not a request object
}

// RequestQueue holds the requests read and not answered yet: those the reader thread sends through
// `requests`, and those taken from it to see whether a later request supersedes the current one.
@[heap]
struct RequestQueue {
	requests chan ServerRequest
mut:
	waiting []ServerRequest
	current string // the files of the request being answered
}

// next is the next request to answer, or none once stdin ended and every request was answered.
fn (mut q RequestQueue) next() ?ServerRequest {
	if q.waiting.len > 0 {
		first := q.waiting[0]
		q.waiting.delete(0)
		return first
	}
	return <-q.requests or { return none }
}

// stop tells whether a request read after the current one lints the same files (rules.LintStop):
// only the answer to the last one matters.
fn (mut q RequestQueue) stop() bool {
	for {
		mut later := ServerRequest{}
		if q.requests.try_pop(mut later) != .success {
			break
		}
		q.waiting << later
	}
	return q.current != '' && q.waiting.any(it.files == q.current)
}

// read_requests reads the requests of stdin, one per line, until it ends.
fn read_requests(requests chan ServerRequest) {
	for {
		line := os.get_raw_line()
		if line.len == 0 {
			break
		}
		if line.trim_space().len == 0 {
			continue
		}
		requests <- parse_request(line)
	}
	requests.close()
}

fn parse_request(line string) ServerRequest {
	root := json2.decode[json2.Any](line) or {
		return ServerRequest{
			error: 'veslint: a request is one JSON object per line\n'
		}
	}
	if root !is map[string]json2.Any {
		return ServerRequest{
			error: 'veslint: a request is a JSON object\n'
		}
	}
	request := root.as_map()
	return ServerRequest{
		request: request
		files:   request_list(request, 'files').join('\n')
	}
}

@[heap]
struct Server {
mut:
	timeout       time.Duration
	parser        treesitter.Parser
	tsx_parser    treesitter.Parser
	client        &tsgo.Client = unsafe { nil }
	open_projects []string // the tsconfig.json files tsgo has open
	snap          tsgo.UpdateSnapshotResponse
	projects      map[string]string // the project of each tsconfig.json in that snapshot
	checkers      map[string]&rules.Checker
	// asts are the declaration ASTs of each tsconfig.json, kept from one snapshot to the next
	// without the files tsgo reads again (forget_asts)
	asts map[string]&rules.DeclarationAsts
	// served are the texts tsgo reads instead of the files on disk: unsaved text, and the decoded
	// text of a file that is not valid UTF-8 (as the command line serves it).
	served  map[string]string
	changes tsgo.FileChangeSet // what changed since the last snapshot
	queue   &RequestQueue = unsafe { nil }
}

// serve answers requests until stdin ends.
fn serve(timeout time.Duration) {
	requests := chan ServerRequest{cap: 64}
	mut s := &Server{
		timeout:    timeout
		queue:      &RequestQueue{
			requests: requests
		}
		parser:     treesitter.new_parser() or {
			eprintln('veslint: ${err.msg()}')
			exit(1)
		}
		tsx_parser: treesitter.new_tsx_parser() or {
			eprintln('veslint: ${err.msg()}')
			exit(1)
		}
	}
	defer {
		s.stop()
		s.parser.close()
		s.tsx_parser.close()
	}
	reader := spawn read_requests(requests)
	for {
		request := s.queue.next() or { break }
		println(json2.encode(s.handle(request)))
	}
	reader.wait()
}

// stop shuts tsgo down; the next request starts it again, with what it has to serve.
fn (mut s Server) stop() {
	if s.client != unsafe { nil } {
		s.client.shutdown()
		s.client = unsafe { nil }
	}
	s.open_projects = []
	s.projects = map[string]string{}
	s.checkers = map[string]&rules.Checker{}
	s.asts = map[string]&rules.DeclarationAsts{}
	s.changes = tsgo.FileChangeSet{}
}

// forget_asts drops the declaration ASTs of the files tsgo reads again in the next snapshot.
fn (mut s Server) forget_asts(changes tsgo.FileChangeSet) {
	if changes.invalidate_all {
		s.asts = map[string]&rules.DeclarationAsts{}
		return
	}
	for _, mut asts in s.asts {
		for path in changes.changed {
			asts.forget(path)
		}
		for path in changes.created {
			asts.forget(path)
		}
		for path in changes.deleted {
			asts.forget(path)
		}
	}
}

// request_list is a list of strings of a request; what is not a string is skipped.
fn request_list(request map[string]json2.Any, key string) []string {
	value := request[key] or { return [] }
	if value !is []json2.Any {
		return []
	}
	return value.as_array().filter(it is string).map(it.str())
}

// request_paths is a list of paths of a request, made absolute.
fn request_paths(request map[string]json2.Any, key string) []string {
	return request_list(request, key).map(os.abs_path(it))
}

fn request_string(request map[string]json2.Any, key string) string {
	value := request[key] or { return '' }
	return if value is string { value } else { '' }
}

fn request_bool(request map[string]json2.Any, key string, default_value bool) bool {
	value := request[key] or { return default_value }
	return if value is bool { value } else { default_value }
}

fn (mut s Server) handle(item ServerRequest) ServerAnswer {
	if item.error != '' {
		return ServerAnswer{
			id:     -1
			code:   2
			stderr: item.error
		}
	}
	request := item.request
	id := (request['id'] or { json2.Any(i64(-1)) }).i64()
	s.changes.changed << request_paths(request, 'changed')
	s.changes.created << request_paths(request, 'created')
	s.changes.deleted << request_paths(request, 'deleted')
	if request_bool(request, 'reset', false) {
		s.changes.invalidate_all = true
	}
	for path in request_paths(request, 'forget') {
		s.stop_serving(path)
	}
	mut texts := map[string]string{}
	if value := request['texts'] {
		if value is map[string]json2.Any {
			for path, text in value {
				if text is string {
					texts[os.abs_path(path)] = text
				}
			}
		}
	}
	for path, text in texts {
		s.set_served(path, text)
	}
	// As they are given: they are printed so.
	files := request_list(request, 'files')
	if files.len == 0 {
		return ServerAnswer{
			id: id
		}
	}
	config := request_string(request, 'config')
	if config == '' {
		return ServerAnswer{
			id:     id
			code:   2
			stderr: 'veslint: a request with files needs a configuration (`config`)\n'
		}
	}
	s.queue.current = item.files
	if s.queue.stop() {
		return ServerAnswer{
			id:        id
			cancelled: true
		}
	}
	return s.lint(id, config, request_string(request, 'project'), files, texts, request_bool(request,
		'fixes', true))
}

// stop_serving makes tsgo read a file from disk again.
fn (mut s Server) stop_serving(path string) {
	if path !in s.served {
		return
	}
	s.served.delete(path)
	if s.client != unsafe { nil } {
		s.client.stop_serving(path)
	}
	s.changes.changed << path
}

// set_served gives tsgo `text` for `path` from the next snapshot on.
fn (mut s Server) set_served(path string, text string) {
	if existing := s.served[path] {
		if existing == text {
			return
		}
	}
	s.served[path] = text
	if s.client != unsafe { nil } {
		s.client.serve(path, text)
	}
	s.changes.changed << path
}

// lint lints `files` (as they are given) and answers what the command line would print; `texts`
// are the unsaved texts of the request, by absolute path, already served.
fn (mut s Server) lint(id i64, config string, project string, files []string, texts map[string]string, fixes bool) ServerAnswer {
	mut errors := strings.new_builder(256)
	for path in files {
		if treesitter.is_javascript_path(path) {
			return ServerAnswer{
				id:     id
				code:   2
				stderr: 'veslint: ${path}: veslint only reads TypeScript (.ts, .mts, .cts, .tsx)\n'
			}
		}
	}
	loaded := load_config_for(config, files) or {
		return ServerAnswer{
			id:     id
			code:   2
			stderr: 'veslint: ${err.msg()}\n'
		}
	}
	// The rules and the ignored ones of every configuration, as parse_args gathers them.
	mut selected := []string{}
	mut ignored := []string{}
	for entry in loaded.configs {
		for r in entry.setup.rules {
			if r.name !in selected {
				selected << r.name
			}
		}
		for rule_id in entry.setup.ignored {
			if rule_id !in ignored {
				ignored << rule_id
			}
		}
	}
	if selected.len == 0 {
		return ServerAnswer{
			id:     id
			code:   2
			stderr: 'veslint: ${config}: does not enable any veslint rule (${rules.names.join(', ')})\n'
		}
	}
	if ignored.len > 0 {
		errors.writeln(ignored_rules_warning(ignored))
	}
	lint_configs := []rules.LintConfig{len: loaded.configs.len, init: loaded.lint_config(index)}
	mut project_override := ''
	if project != '' {
		if !os.is_file(project) {
			errors.writeln('veslint: tsconfig ${project} does not exist')
			return ServerAnswer{
				id:     id
				code:   1
				stderr: errors.str()
			}
		}
		project_override = os.abs_path(project)
	}
	mut entries := []RuleFile{cap: files.len}
	mut tsconfigs := []string{}
	for path in files {
		abs_path := os.abs_path(path)
		if note := loaded.file_notes[abs_path] {
			entries << RuleFile{
				path: path
				note: note
			}
			continue
		}
		mut src := ''
		mut has_bom := false
		if text := texts[abs_path] {
			// The text of the editor, without a BOM; the file has one when it starts so on disk.
			src, has_bom = offsets.strip_bom(text)
			has_bom = has_bom || disk_has_bom(abs_path)
		} else {
			disk, bom, not_utf8 := read_source(path) or {
				errors.writeln('veslint: ${err.msg()}')
				return ServerAnswer{
					id:     id
					code:   1
					stderr: errors.str()
				}
			}
			src = disk
			has_bom = bom
			if not_utf8 {
				s.set_served(abs_path, disk)
			} else {
				s.stop_serving(abs_path)
			}
		}
		named := if project_override == '' {
			loaded.named_projects(abs_path)
		} else {
			[]string{}
		}
		tsconfig := if named.len > 0 {
			''
		} else if project_override != '' {
			project_override
		} else {
			find_tsconfig(abs_path) or {
				errors.writeln('veslint: ${err.msg()}')
				return ServerAnswer{
					id:     id
					code:   1
					stderr: errors.str()
				}
			}
		}
		for t in named {
			if t !in tsconfigs {
				tsconfigs << t
			}
		}
		if tsconfig != '' && tsconfig !in tsconfigs {
			tsconfigs << tsconfig
		}
		entries << RuleFile{
			path:     path
			abs_path: abs_path
			tsconfig: tsconfig
			named:    named
			src:      src
			has_bom:  has_bom
		}
	}
	mut out := strings.new_builder(4096)
	mut problems := 0
	mut warnings := 0
	if tsconfigs.len > 0 {
		s.snapshot_for(tsconfigs) or {
			s.stop()
			errors.writeln('veslint: ${err.msg()}')
			return ServerAnswer{
				id:     id
				code:   1
				stderr: errors.str()
			}
		}
		// The files whose configuration names projects take the first one that has them.
		opened := assign_named_projects(mut entries, s.snap) or {
			errors.writeln('veslint: ${err.msg()}')
			return ServerAnswer{
				id:     id
				code:   1
				stderr: errors.str()
			}
		}
		if opened.len > 0 {
			mut all := tsconfigs.clone()
			all << opened
			s.snapshot_for(all) or {
				s.stop()
				errors.writeln('veslint: ${err.msg()}')
				return ServerAnswer{
					id:     id
					code:   1
					stderr: errors.str()
				}
			}
		}
	}
	mut stats := rules.Stats{}
	for f in entries {
		if s.queue.stop() {
			return ServerAnswer{
				id:        id
				cancelled: true
			}
		}
		if f.note != '' {
			out.writeln('${f.path}:0:0\t${rules.problem_rule}\twarning\t${tsv_field(f.note)}')
			problems++
			warnings++
			continue
		}
		lint_config := lint_configs[loaded.file_config[f.abs_path] or { 0 }]
		project_id := s.projects[f.tsconfig] or { '' }
		if project_id !in s.checkers {
			mut checker := rules.new_checker(s.client, s.snap.snapshot, project_id, project_options(s.snap,
				project_id)) or {
				s.stop()
				errors.writeln('veslint: ${err.msg()}')
				return ServerAnswer{
					id:     id
					code:   1
					stderr: errors.str()
				}
			}
			checker.set_project_directory(os.dir(f.tsconfig))
			mut asts := s.asts[f.tsconfig] or {
				created := &rules.DeclarationAsts{}
				s.asts[f.tsconfig] = created
				created
			}
			checker.share_declaration_asts(asts)
			s.checkers[project_id] = checker
		}
		mut checker := s.checkers[project_id] or { continue }
		checker.set_lint_stop(s.queue)
		checker.set_has_bom(f.has_bom)
		result := checker.lint_file(if treesitter.uses_jsx_dialect(f.path) {
			s.tsx_parser
		} else {
			s.parser
		}, lint_config, f.src, f.abs_path, mut stats) or {
			if err.msg() == rules.lint_stopped {
				// Given up between two rules: what the checker holds is what tsgo answered.
				return ServerAnswer{
					id:        id
					cancelled: true
				}
			}
			// The checkers of this snapshot may hold what that run left half done.
			s.stop()
			errors.writeln('veslint: ${f.path}: ${err.msg()}')
			return ServerAnswer{
				id:     id
				code:   1
				stdout: out.str()
				stderr: errors.str()
			}
		}
		report := file_report(f.path, f.src, result, fixes)
		errors.write_string(report.stderr)
		out.write_string(report.stdout)
		problems += report.problems
		warnings += report.warnings
	}
	errors.writeln(summary_line(problems, files.len, warnings))
	return ServerAnswer{
		id:     id
		code:   if problems - warnings > 0 { 1 } else { 0 }
		stdout: out.str()
		stderr: errors.str()
	}
}

// snapshot_for makes sure tsgo runs, has `tsconfigs` open and has read what changed: the snapshot
// of the last request is kept when nothing did, with the checkers and what they already asked.
fn (mut s Server) snapshot_for(tsconfigs []string) ! {
	if s.client == unsafe { nil } {
		mut client := tsgo.start_serving(tsgo.binary_path(), os.dir(tsconfigs[0]), s.timeout)!
		for path, text in s.served {
			client.serve(path, text)
		}
		s.client = client
		_ = s.client.initialize()!
		s.open_projects = tsconfigs.clone()
		s.snap = s.client.create_snapshot(s.open_projects)!
		s.projects = map_projects(s.open_projects, s.snap)!
		s.checkers = map[string]&rules.Checker{}
		s.asts = map[string]&rules.DeclarationAsts{}
		s.changes = tsgo.FileChangeSet{}
		return
	}
	mut opened := []string{}
	for tsconfig in tsconfigs {
		if tsconfig !in s.open_projects {
			s.open_projects << tsconfig
			opened << tsconfig
		}
	}
	if opened.len == 0 && s.changes.is_empty() {
		return
	}
	previous := s.snap.snapshot
	s.forget_asts(s.changes)
	s.snap = s.client.update_snapshot_files(s.snap, opened, s.changes)!
	s.changes = tsgo.FileChangeSet{}
	s.projects = map_projects(s.open_projects, s.snap)!
	s.checkers = map[string]&rules.Checker{}
	if previous != s.snap.snapshot {
		s.client.release_snapshot(previous)!
	}
}

// disk_has_bom: the file starts with a UTF-8 BOM on disk.
fn disk_has_bom(path string) bool {
	mut f := os.open(path) or { return false }
	defer {
		f.close()
	}
	mut head := []u8{len: 3}
	n := f.read(mut head) or { return false }
	return n == 3 && head.bytestr() == offsets.utf8_bom
}
