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
	// served are the texts given to tsgo instead of the files on disk, by path (start_with_files);
	// serves_files tells that tsgo was started with the readFile callback.
	served       map[string]string
	serves_files bool
	// symbols are the symbols tsgo sent, by the int the rules know them by (see symbols.v).
	symbols SymbolTable
	// The module resolver of each project and the names each module file exports (modules.v).
	module_resolvers map[string]int
	module_exports   map[string][]string
	program_files    map[string][]string // by `snapshot:project` (source_file_names)
}

// tsgo_path returns the path of the pinned binary, relative to the veslint executable.
pub fn binary_path() string {
	return os.join_path(os.dir(os.executable()), rel_path)
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

// start_serving starts tsgo like start, always with its readFile callback, for a process that
// gives it text later (`veslint --server`: the unsaved text of an editor, see serve).
pub fn start_serving(bin string, cwd string, timeout time.Duration) !&Client {
	return start_process(bin, cwd, timeout, map[string]string{}, true)
}

fn start_process(bin string, cwd string, timeout time.Duration, files map[string]string, callbacks bool) !&Client {
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
	if callbacks {
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
	}
}

// serve gives tsgo `text` as the content of `path` from the next snapshot on, instead of the file
// on disk (a client of start_serving).
pub fn (mut c Client) serve(path string, text string) {
	c.served[path_key(path)] = text
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
			if !c.serves_files || f.method != 'readFile' {
				return c.fail('protocol: tsgo asked for the `${f.method}` callback, but veslint registers no callbacks')
			}
			answered := c.answer_read_file(f.payload) or { return c.fail(err.msg()) }
			if !answered {
				return c.fail('timeout: tsgo did not accept the answer to its `readFile` callback within ${c.timeout}')
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

// request_count gives how many requests were sent (for --bench).
pub fn (c &Client) request_count() int {
	return c.requests
}
