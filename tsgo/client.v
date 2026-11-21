module tsgo

import json2
import os
import time

// Client of `tsc --api` (TypeScript 7.1.0-beta) that speaks its protocol directly.
// See PROMPT.md §3.1 (protocol) and §3.3 (process, threads and shutdown). Its pipes are read and
// written in client_nix.c.v (POSIX) and client_windows.c.v.

const required_version = 'Version 7.1.0-beta'

// rel_path is the path of the compiler of this machine inside the directory that has
// `node_modules` (see platform.v).
pub const rel_path = binary_rel_path()

const shutdown_grace = 2 * time.second

const stderr_tail_bytes = 16384

const stderr_tail_lines = 50

// A write of at most PIPE_BUF bytes does not block if poll() reports POLLOUT.
const pipe_buf = 4096

const read_chunk = 65536

// ReaderEvent is what the reader thread hands to the main thread.
struct ReaderEvent {
	frame Frame
	eof   bool
	err   string
}

@[heap]
pub struct Client {
mut:
	proc          &os.Process = unsafe { nil }
	events        chan ReaderEvent
	reader        thread
	stderr_reader thread string
	stderr_tail   string
	closed        bool
	reader_done   bool // the final reader event (EOF or error) was already received
	timeout       time.Duration
	requests      int // requests sent (for --bench)
	// the requests of each method and their time, from the call to the answer (for --bench)
	methods map[string]MethodStat
	// time spent in TypeScript's calls with the transport of this process (for --bench)
	inproc_time time.Duration
	// served are the texts given to tsgo instead of the files on disk, by path (start_with_files);
	// serves_files tells that tsgo was started with the readFile callback.
	served       map[string]string
	serves_files bool
	// virtual are files that exist only for tsgo (the TypeScript twin of a .vue file, see rules/vue_file.v):
	// with the fileExists, stat and getAccessibleEntries callbacks, tsgo finds them as files, also
	// when it lists their directory, and readFile gives their served text. By path_key; the
	// basenames of the virtual files of each directory are in virtual_dirs.
	virtual      map[string]bool
	virtual_dirs map[string][]string
	virtual_fs   bool
	// symbols are the symbols tsgo sent, by the int the rules know them by (see symbols.v).
	symbols SymbolTable
	// The module resolver of each project and the names each module file exports (modules.v).
	module_resolvers map[string]int
	module_exports   map[string][]string
	program_files    map[string][]string // by `snapshot:project` (source_file_names)
	// inproc is the handle of TypeScript's session in this process (inproc.c.v); 0 with the
	// process transport.
	inproc i64
	// worker is the lint worker this client asks for, 0 for the session's own checker (see
	// worker_client); a worker's client does not close the session it shares.
	worker int
	shared bool
	// no_helpers makes the rules walk types themselves even with TypeScript in this process
	// (VESLINT_TSGO_HELPERS=0, to compare both ways; see rule_helpers.v), and asks for types
	// without sent_types.v.
	no_helpers bool
	// The types this client was sent whole, by `snapshot project` (sent_types.v).
	sent_types map[string]&SentTypes
}

// binary_path returns the path of the pinned binary for the veslint executable (see
// binary_path_from).
pub fn binary_path() string {
	return binary_path_from(os.dir(os.executable()))
}

// binary_path_from is the compiler in the `node_modules` of `dir` (a release archive, a build) or,
// as Node resolves a dependency, in the closest `node_modules` above it that has it: npm installs
// the compiler of the package @marcrock22/veslint-<platform>-<arch> beside the package or in a
// parent `node_modules`. Without one, the path in `dir`, which the error names.
pub fn binary_path_from(dir string) string {
	mut current := dir
	for {
		candidate := os.join_path(current, rel_path)
		if os.is_file(candidate) {
			return candidate
		}
		parent := os.dir(current)
		if parent == current || !os.is_abs_path(parent) {
			break
		}
		current = parent
	}
	return os.join_path(dir, rel_path)
}

// start_tsgo checks the binary and its version, and starts `tsc --api --cwd <cwd>` with a thread
// that reads its messages and another one that drains its stderr.
pub fn start(bin string, cwd string, timeout time.Duration) !&Client {
	return start_with_files(bin, cwd, timeout, map[string]string{})
}

// start_with_files starts tsgo like start and, if `files` is not empty, with its readFile
// callback (`--callbacks=readFile`): tsgo then asks for the text of every file it reads, and gets
// the one of `files` for those paths and "read it from disk" for the others. It is how a file that
// is not valid UTF-8 is read by tsgo as ESLint reads it (see offsets.decode_utf8).
pub fn start_with_files(bin string, cwd string, timeout time.Duration, files map[string]string) !&Client {
	return start_process(bin, cwd, timeout, files, files.len > 0)
}

// start_virtual starts tsgo like start_with_files, with `virtual` files too: files that are not
// on disk and that tsgo sees as files with that text (see Client.virtual).
pub fn start_virtual(bin string, cwd string, timeout time.Duration, files map[string]string, virtual map[string]string) !&Client {
	mut served := files.clone()
	for path, text in virtual {
		served[path] = text
	}
	mut c := start_process_with(bin, cwd, timeout, served, true, true)!
	for path, _ in virtual {
		c.add_virtual(path)
	}
	return c
}

// add_virtual makes `path`, which is served, a file for tsgo though it is not on disk.
fn (mut c Client) add_virtual(path string) {
	key := path_key(path)
	if key in c.virtual {
		return
	}
	c.virtual[key] = true
	dir := path_key(os.dir(path))
	c.virtual_dirs[dir] << os.file_name(path)
	if c.inproc != 0 {
		c.inproc_set_virtual(path, true)
	}
}

// remove_virtual makes `path` no longer a file for tsgo (tsgo has to be told it was deleted).
pub fn (mut c Client) remove_virtual(path string) {
	key := path_key(path)
	c.served.delete(key)
	c.virtual.delete(key)
	dir := path_key(os.dir(path))
	name := os.file_name(path)
	if names := c.virtual_dirs[dir] {
		c.virtual_dirs[dir] = names.filter(it != name)
	}
	if c.inproc != 0 {
		c.inproc_set_virtual(path, false)
	}
}

// has_virtual_fs: the client was started with virtual files (start_virtual), so it can be given
// more (serve_virtual).
pub fn (c &Client) has_virtual_fs() bool {
	return c.virtual_fs
}

// serve_virtual makes `path` a virtual file with `text` from the next snapshot on (a client of
// start_virtual); tsgo has to be told it was created (FileChangeSet.created) when it is new, which
// this tells.
pub fn (mut c Client) serve_virtual(path string, text string) bool {
	c.served[path_key(path)] = text
	if c.inproc != 0 {
		c.inproc_serve(path, text)
	}
	is_new := path_key(path) !in c.virtual
	c.add_virtual(path)
	return is_new
}

// start_serving starts tsgo like start, always with its readFile callback, for a process that
// gives it text later (`veslint --server`: the unsaved text of an editor, see serve).
pub fn start_serving(bin string, cwd string, timeout time.Duration) !&Client {
	return start_process(bin, cwd, timeout, map[string]string{}, true)
}

fn start_process(bin string, cwd string, timeout time.Duration, files map[string]string, callbacks bool) !&Client {
	return start_process_with(bin, cwd, timeout, files, callbacks, false)
}

// start_process_with starts TypeScript with the transport of VESLINT_TSGO: in this process
// (inproc.c.v) or `tsc --api` (start_tsc_process).
fn start_process_with(bin string, cwd string, timeout time.Duration, files map[string]string, callbacks bool, virtual_fs bool) !&Client {
	return match transport_from_env()! {
		.inproc { start_inproc(bin, cwd, timeout, files, callbacks, virtual_fs)! }
		.process { start_tsc_process(bin, cwd, timeout, files, callbacks, virtual_fs)! }
	}
}

fn start_tsc_process(bin string, cwd string, timeout time.Duration, files map[string]string, callbacks bool, virtual_fs bool) !&Client {
	if !os.is_file(bin) || !os.is_executable(bin) {
		return missing_binary_error(bin, current_host())
	}
	output, exit_code := version_output(bin, timeout)!
	got := output.trim_space()
	if exit_code != 0 || got != required_version {
		return error('${bin} answered `${got}` and `${required_version}` was expected; the protocol has no version, so veslint cannot continue')
	}
	mut p := os.new_process(bin)
	mut args := ['--api', '--cwd', cwd]
	if virtual_fs {
		args << '--callbacks=readFile,fileExists,stat,getAccessibleEntries'
	} else if callbacks {
		args << '--callbacks=readFile'
	}
	p.set_args(args)
	p.set_redirect_stdio()
	p.run()
	if p.status != .running {
		return error('could not start ${bin}: ${p.err}')
	}
	adopt_pipes(mut p)
	events := chan ReaderEvent{cap: 16}
	return &Client{
		proc:          p
		events:        events
		reader:        spawn read_frames(p.stdio_fd[1], events)
		stderr_reader: spawn read_stderr_tail(p.stdio_fd[2])
		timeout:       timeout
		served:        served_by_key(files)
		serves_files:  callbacks
		virtual_fs:    virtual_fs
	}
}

// serve gives tsgo `text` as the content of `path` from the next snapshot on, instead of the file
// on disk (a client of start_serving).
pub fn (mut c Client) serve(path string, text string) {
	c.served[path_key(path)] = text
	if c.inproc != 0 {
		c.inproc_serve(path, text)
	}
}

// served_by_key keys the served texts by path_key, as tsgo's readFile callback names them.
fn served_by_key(files map[string]string) map[string]string {
	mut served := map[string]string{}
	for path, text in files {
		served[path_key(path)] = text
	}
	return served
}

// stop_serving makes tsgo read a file from disk again: after veslint rewrote it (`--fix`), the
// text on disk is the one to read.
pub fn (mut c Client) stop_serving(path string) {
	c.served.delete(path_key(path))
	if c.inproc != 0 {
		c.inproc_stop_serving(path)
	}
}

// FileContent is the answer to a readFile callback that has the text (encodeFileSystemCallbackResult
// in dist/api/fsCallbacks.js).
struct FileContent {
	kind  string
	value string
}

// read_from_disk is the answer to a callback that lets tsgo use the file system (serverFS.useOS).
const read_from_disk = '{"kind":"useOS"}'

// answer_read_file answers tsgo's readFile callback for a path (its payload, a JSON string): the
// served text or "read it from disk".
fn (mut c Client) answer_read_file(payload string) !bool {
	path := json2.decode[string](payload) or {
		return error('protocol: the readFile callback of tsgo has no path (${payload})')
	}
	answer := if text := c.served[path_key(path)] {
		json2.encode(FileContent{
			kind:  'value'
			value: text
		})
	} else {
		read_from_disk
	}
	return write_frame(c.proc.stdio_fd[0], encode_frame(msg_call_response, 'readFile', answer),
		c.timeout) or {
		return error('tsgo exited unexpectedly (EOF) while it read `${path}`: ${err.msg()}')
	}
}

// answer_virtual_fs answers the fileExists, stat and getAccessibleEntries callbacks: a virtual
// file exists (with a stat tsgo makes up), a directory that has virtual files lists them besides
// what is on disk, and anything else is tsgo's to look up on disk.
fn (mut c Client) answer_virtual_fs(method string, payload string) !bool {
	path := json2.decode[string](payload) or {
		return error('protocol: the ${method} callback of tsgo has no path (${payload})')
	}
	key := path_key(path)
	answer := match method {
		'fileExists' {
			if key in c.virtual { '{"kind":"value","value":true}' } else { read_from_disk }
		}
		'stat' {
			if key in c.virtual { '{"kind":"fakeStat"}' } else { read_from_disk }
		}
		'getAccessibleEntries' {
			if names := c.virtual_dirs[key] {
				directory_entries(path, names)
			} else {
				read_from_disk
			}
		}
		else {
			return error('protocol: tsgo asked for the `${method}` callback, which veslint does not register')
		}
	}
	return write_frame(c.proc.stdio_fd[0], encode_frame(msg_call_response, method, answer),
		c.timeout) or {
		return error('tsgo exited unexpectedly (EOF) during its ${method} callback for `${path}`: ${err.msg()}')
	}
}

// directory_entries is the answer to getAccessibleEntries for a directory with virtual files: its
// files and directories on disk (a symbolic link counts as what it points to, as TypeScript's
// getAccessibleFileSystemEntries counts it) and the virtual ones.
fn directory_entries(dir string, virtual_names []string) string {
	mut files := []string{}
	mut directories := []string{}
	for name in os.ls(dir) or { []string{} } {
		full := os.join_path(dir, name)
		if os.is_dir(full) {
			directories << name
		} else if os.is_file(full) {
			files << name
		}
	}
	for name in virtual_names {
		if name !in files {
			files << name
		}
	}
	return '{"kind":"value","value":{"files":${json2.encode(files)},"directories":${json2.encode(directories)}}}'
}

// read_frames runs in its own thread: it reads tsgo's stdout with blocking reads and hands over
// complete messages. A 0-byte read is EOF (tsgo exited).
fn read_frames(fd int, events chan ReaderEvent) {
	mut decoder := FrameDecoder{}
	mut buf := []u8{len: read_chunk}
	for {
		n := read_some(fd, mut buf)
		if n <= 0 {
			events <- ReaderEvent{
				eof: true
			}
			return
		}
		decoder.push(buf[..n])
		for {
			frame, complete := decoder.next() or {
				events <- ReaderEvent{
					err: err.msg()
				}
				return
			}
			if !complete {
				break
			}
			events <- ReaderEvent{
				frame: frame
			}
		}
	}
}

// read_stderr_tail runs in its own thread: it drains tsgo's stderr so it never blocks writing,
// and returns its last bytes when tsgo exits.
fn read_stderr_tail(fd int) string {
	mut tail := []u8{}
	mut buf := []u8{len: 4096}
	for {
		n := read_some(fd, mut buf)
		if n <= 0 {
			break
		}
		tail << buf[..n]
		if tail.len > 2 * stderr_tail_bytes {
			tail = tail[tail.len - stderr_tail_bytes..].clone()
		}
	}
	if tail.len > stderr_tail_bytes {
		tail = tail[tail.len - stderr_tail_bytes..].clone()
	}
	return tail.bytestr()
}

// request sends a request and waits for its response (the protocol is serial). The timeout covers
// the write and the wait. Returns the JSON payload of the response.
fn (mut c Client) request(method string, payload string) !string {
	if c.closed {
		return error('tsgo is already closed')
	}
	if c.inproc != 0 {
		return c.inproc_request(method, payload)
	}
	sw := time.new_stopwatch()
	written := write_frame(c.proc.stdio_fd[0], encode_frame(msg_request, method, payload),
		c.timeout) or {
		return c.fail('tsgo exited unexpectedly (EOF) during `${method}`: ${err.msg()}')
	}
	if !written {
		return c.fail('timeout: tsgo did not accept the `${method}` request within ${c.timeout}')
	}
	c.requests++
	// While it answers, tsgo may ask for the text of the files it reads (readFile callbacks).
	for {
		remaining := c.timeout - sw.elapsed()
		if remaining <= 0 {
			return c.fail('timeout: tsgo did not answer `${method}` within ${c.timeout}')
		}
		mut ev := ReaderEvent{}
		select {
			received := <-c.events {
				ev = received
			}
			remaining {
				return c.fail('timeout: tsgo did not answer `${method}` within ${c.timeout}')
			}
		}
		if ev.eof || ev.err != '' {
			c.reader_done = true
		}
		if ev.eof {
			return c.fail('tsgo exited unexpectedly (EOF) during `${method}`')
		}
		if ev.err != '' {
			return c.fail(ev.err)
		}
		f := ev.frame
		if f.typ == msg_call {
			if !c.serves_files || (f.method != 'readFile' && !c.virtual_fs) {
				return c.fail('protocol: tsgo asked for the `${f.method}` callback, but veslint registers no callbacks')
			}
			answered := if f.method == 'readFile' {
				c.answer_read_file(f.payload) or { return c.fail(err.msg()) }
			} else {
				c.answer_virtual_fs(f.method, f.payload) or { return c.fail(err.msg()) }
			}
			if !answered {
				return c.fail('timeout: tsgo did not accept the answer to its `${f.method}` callback within ${c.timeout}')
			}
			continue
		}
		if f.method != method {
			return c.fail('protocol: expected the response to `${method}` and got `${f.method}` (type ${f.typ})')
		}
		if f.typ == msg_error {
			return error('tsgo rejected `${method}`: ${f.payload}')
		}
		if f.typ != msg_response {
			return c.fail('protocol: unknown message type (${f.typ}) in the response to `${method}`')
		}
		c.count_method(method, sw.elapsed())
		return f.payload
	}
	return error('unreachable')
}

// is_panic tells whether an error is a request tsgo rejected because it panicked while answering
// it: the rejection carries the Go panic. The connection survives it.
pub fn is_panic(err IError) bool {
	msg := err.msg()
	return msg.starts_with('tsgo rejected `') && msg.contains('`: panic: ')
}

// fail closes tsgo and returns the error together with the last lines of its stderr.
fn (mut c Client) fail(msg string) IError {
	c.shutdown()
	tail := last_lines(c.stderr_tail, stderr_tail_lines)
	if tail == '' {
		return error(msg)
	}
	return error('${msg}\n--- last lines of tsgo stderr ---\n${tail}')
}

fn last_lines(s string, n int) string {
	lines := s.trim_space().split_into_lines()
	if lines.len <= n {
		return lines.join('\n')
	}
	return lines[lines.len - n..].join('\n')
}

// shutdown closes tsgo as PROMPT.md §3.3 says: it closes its stdin (tsgo ignores SIGTERM while
// stdin is open), waits up to `shutdown_grace` and, if it did not exit, kills it. Then it waits
// for both reader threads. It is idempotent.
pub fn (mut c Client) shutdown() {
	if c.closed {
		return
	}
	c.closed = true
	if c.shared {
		return
	}
	if c.inproc != 0 {
		c.inproc_close()
		return
	}
	if c.proc.stdio_fd[0] != -1 {
		close_fd(c.proc.stdio_fd[0])
		c.proc.stdio_fd[0] = -1
	}
	sw := time.new_stopwatch()
	for c.proc.is_alive() && sw.elapsed() < shutdown_grace {
		time.sleep(2 * time.millisecond)
	}
	if c.proc.is_alive() {
		kill_now(mut c.proc)
	}
	c.proc.wait()
	// The reader only exits after handing over a final event (EOF or error). If tsgo sent extra
	// messages and the channel is full, the reader waits: it is drained up to that event.
	for !c.reader_done {
		ev := <-c.events
		if ev.eof || ev.err != '' {
			c.reader_done = true
		}
	}
	c.reader.wait()
	c.stderr_tail = c.stderr_reader.wait()
	c.proc.close()
	release_pipes(mut c.proc)
}

// MethodStat is how many requests of a method a client sent and how long they took, from the
// request to its answer (with TypeScript in this process: the call, which includes TypeScript's
// decoding of the parameters and its encoding of the answer, not the client's decoding).
pub struct MethodStat {
pub mut:
	count int
	time  time.Duration
}

// method_stats are the requests of each method (for --bench).
pub fn (c &Client) method_stats() map[string]MethodStat {
	return c.methods
}

fn (mut c Client) count_method(method string, elapsed time.Duration) {
	mut stat := c.methods[method] or { MethodStat{} }
	stat.count++
	stat.time += elapsed
	c.methods[method] = stat
}

// request_count gives how many requests were sent (for --bench).
pub fn (c &Client) request_count() int {
	return c.requests
}
