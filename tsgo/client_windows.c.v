module tsgo

import os
import time

// The Windows side of the pipes of client.v (client_nix.c.v is the POSIX one); upstream builds
// veslint on Linux only. V's os.Process keeps the pipes of a child as HANDLEs in os.WProcess, not
// in p.stdio_fd, and on Windows its close() closes none of them: adopt_pipes puts them in
// p.stdio_fd, where the rest of the client looks for them, and release_pipes closes them. A HANDLE
// fits in an int, which V makes as wide as a pointer (and on 64-bit Windows a HANDLE has 32
// significant bits anyway: that is how 32-bit processes share handles).

fn C.SetNamedPipeHandleState(pipe voidptr, mode &u32, max_collection_count voidptr, collect_data_timeout voidptr) bool

fn handle(fd int) voidptr {
	return voidptr(fd)
}

// adopt_pipes takes the pipes of a process started with set_redirect_stdio and makes its stdin
// non-blocking (PIPE_NOWAIT) for write_frame. Should that fail, a write blocks until the child
// reads, which only matters for a child that stops reading.
fn adopt_pipes(mut p os.Process) {
	w := unsafe { &os.WProcess(p.wdata) }
	p.stdio_fd[0] = int(voidptr(w.child_stdin_write))
	p.stdio_fd[1] = int(voidptr(w.child_stdout_read))
	p.stdio_fd[2] = int(voidptr(w.child_stderr_read))
	mode := u32(C.PIPE_NOWAIT)
	C.SetNamedPipeHandleState(handle(p.stdio_fd[0]), &mode, unsafe { nil }, unsafe { nil })
}

// release_pipes closes the HANDLEs adopt_pipes took that are still open, once nothing reads them.
fn release_pipes(mut p os.Process) {
	for i in 0 .. 3 {
		if p.stdio_fd[i] > 0 {
			C.CloseHandle(handle(p.stdio_fd[i]))
			p.stdio_fd[i] = -1
		}
	}
}

fn close_fd(fd int) {
	C.CloseHandle(handle(fd))
}

// kill_now ends the process at once (TerminateProcess); the wait() that follows reaps it.
fn kill_now(mut p os.Process) {
	p.signal_kill()
}

// read_some does a blocking read into `buf`. Returns the bytes read; 0 is EOF (the other end is
// closed: ERROR_BROKEN_PIPE) and -1 another error.
fn read_some(fd int, mut buf []u8) int {
	for {
		mut n := u32(0)
		if C.ReadFile(handle(fd), unsafe { &buf[0] }, u32(buf.len), &n, unsafe { nil }) {
			if n > 0 {
				return int(n)
			}
			// A read of 0 bytes that succeeds is a write of 0 bytes at the other end, not EOF.
			continue
		}
		return if C.GetLastError() == u32(C.ERROR_BROKEN_PIPE) { 0 } else { -1 }
	}
	return 0
}

// pipe_avail tells how many bytes a read of a pipe gets without blocking; -1 when it is at EOF (the
// other end is closed and nothing is left) or fails.
fn pipe_avail(fd int) int {
	mut avail := u32(0)
	if C.PeekNamedPipe(handle(fd), unsafe { nil }, 0, unsafe { nil }, voidptr(&avail), unsafe { nil }) {
		return int(avail)
	}
	return -1
}

// version_output runs `<bin> --version` and returns what it wrote (its stdout and then its stderr)
// and its exit code, with the timeout of a request, as the POSIX one does. There is no poll() for
// pipes: PeekNamedPipe tells which one has something, and the loop sleeps while neither has.
fn version_output(bin string, timeout time.Duration) !(string, int) {
	mut p := os.new_process(bin)
	p.set_args(['--version'])
	p.set_redirect_stdio()
	p.run()
	if p.status != .running {
		return error('could not start ${bin}: ${p.err}')
	}
	adopt_pipes(mut p)
	// It gets no input.
	close_fd(p.stdio_fd[0])
	p.stdio_fd[0] = -1
	sw := time.new_stopwatch()
	mut fds := [p.stdio_fd[1], p.stdio_fd[2]]
	mut texts := [[]u8{}, []u8{}]
	mut buf := []u8{len: 4096}
	mut timed_out := false
	for fds[0] != -1 || fds[1] != -1 {
		if sw.elapsed() >= timeout {
			timed_out = true
			break
		}
		mut idle := true
		for i in 0 .. 2 {
			if fds[i] == -1 {
				continue
			}
			avail := pipe_avail(fds[i])
			if avail == 0 {
				continue
			}
			idle = false
			n := if avail > 0 { read_some(fds[i], mut buf) } else { 0 }
			if n <= 0 {
				fds[i] = -1
				continue
			}
			// The answer is one line: what a binary that floods would add is not kept.
			if texts[i].len < stderr_tail_bytes {
				texts[i] << buf[..n]
			}
		}
		if idle {
			time.sleep(time.millisecond)
		}
	}
	// It closed its output: now it has to exit.
	for !timed_out && p.is_alive() {
		if sw.elapsed() >= timeout {
			timed_out = true
			break
		}
		time.sleep(2 * time.millisecond)
	}
	if timed_out {
		kill_now(mut p)
	}
	p.wait()
	code := p.code
	p.close()
	release_pipes(mut p)
	if timed_out {
		return error('timeout: `${bin} --version` did not finish within ${timeout}, so veslint cannot check that it is `${required_version}`')
	}
	return texts[0].bytestr() + texts[1].bytestr(), code
}

// write_frame writes a message to tsgo's stdin without blocking beyond `timeout`. The pipe is in
// PIPE_NOWAIT mode (adopt_pipes): a write returns at once, having written nothing when the chunk
// does not fit, and is retried a millisecond later. Chunks of at most PIPE_BUF bytes, as on POSIX.
// Returns `false` if the time runs out, and an error if tsgo no longer reads its stdin.
fn write_frame(fd int, data []u8, timeout time.Duration) !bool {
	sw := time.new_stopwatch()
	mut off := 0
	for off < data.len {
		if sw.elapsed() >= timeout {
			return false
		}
		chunk := if data.len - off < pipe_buf { data.len - off } else { pipe_buf }
		mut n := u32(0)
		if !C.WriteFile(handle(fd), unsafe { &data[off] }, u32(chunk), &n, unsafe { nil }) {
			return error('could not write to its stdin (Windows error ${C.GetLastError()})')
		}
		if n == 0 {
			// ponytail: Sleep(1) can last a timer tick (~15 ms), only while tsgo leaves the 64 KiB
			// pipe full; an overlapped pipe and WaitForSingleObject if that ever shows.
			time.sleep(time.millisecond)
		}
		off += int(n)
	}
	return true
}
