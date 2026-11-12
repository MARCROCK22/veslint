module tsgo

import os
import time

// The POSIX side of the pipes of client.v, moved from it as it was; client_windows.c.v is the
// Windows one.

#include <poll.h>

struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}

fn C.poll(fds &C.pollfd, nfds u64, timeout i32) i32

// version_output runs `<bin> --version` and returns what it wrote (its stdout and then its stderr)
// and its exit code. The check has the timeout of a request: the real tsc answers at once, and a
// binary that has not answered and exited by then is killed and reaped, which is an error. Its two
// pipes are read here with poll(), so nothing is left waiting for an EOF that may never come.
fn version_output(bin string, timeout time.Duration) !(string, int) {
	mut p := os.new_process(bin)
	p.set_args(['--version'])
	p.set_redirect_stdio()
	p.run()
	if p.status != .running {
		return error('could not start ${bin}: ${p.err}')
	}
	// It gets no input.
	os.fd_close(p.stdio_fd[0])
	p.stdio_fd[0] = -1
	sw := time.new_stopwatch()
	mut fds := [p.stdio_fd[1], p.stdio_fd[2]]
	mut texts := [[]u8{}, []u8{}]
	mut buf := []u8{len: 4096}
	mut failure := ''
	// Until both pipes are at EOF (poll() ignores a negative descriptor).
	for fds[0] != -1 || fds[1] != -1 {
		remaining := timeout - sw.elapsed()
		if remaining <= 0 {
			failure = 'timeout'
			break
		}
		mut pfds := [2]C.pollfd{}
		for i in 0 .. 2 {
			pfds[i] = C.pollfd{
				fd:     i32(fds[i])
				events: i16(C.POLLIN)
			}
		}
		ready := C.poll(&pfds[0], 2, i32(remaining / time.millisecond) + 1)
		if ready < 0 && C.errno != C.EINTR {
			failure = 'poll failed (errno ${C.errno})'
			break
		}
		if ready <= 0 {
			continue
		}
		for i in 0 .. 2 {
			if pfds[i].revents == 0 {
				continue
			}
			n := read_some(fds[i], mut buf)
			if n <= 0 {
				fds[i] = -1
				continue
			}
			// The answer is one line: what a binary that floods would add is not kept.
			if texts[i].len < stderr_tail_bytes {
				texts[i] << buf[..n]
			}
		}
	}
	// It closed its output: now it has to exit.
	for failure == '' && p.is_alive() {
		if sw.elapsed() >= timeout {
			failure = 'timeout'
			break
		}
		time.sleep(2 * time.millisecond)
	}
	if failure != '' {
		// Not reaped yet, so the pid is still its own. `C.kill` and not `signal_kill()`, as in
		// shutdown().
		C.kill(i32(p.pid), C.SIGKILL)
	}
	p.wait()
	code := p.code
	p.close()
	if failure == 'timeout' {
		return error('timeout: `${bin} --version` did not finish within ${timeout}, so veslint cannot check that it is `${required_version}`')
	}
	if failure != '' {
		return error('could not read the answer of `${bin} --version`: ${failure}')
	}
	return texts[0].bytestr() + texts[1].bytestr(), code
}

// read_some does a blocking read into `buf` and retries it if a signal interrupts it. Returns the
// bytes read; 0 is EOF.
fn read_some(fd int, mut buf []u8) int {
	for {
		n := C.read(i32(fd), unsafe { &buf[0] }, uint(buf.len))
		if n < 0 && C.errno == C.EINTR {
			continue
		}
		return int(n)
	}
	return 0
}

// write_frame writes a message to tsgo's stdin without blocking beyond `timeout`: it waits with
// poll(POLLOUT) and writes chunks of at most PIPE_BUF bytes, which do not block when there is
// room. Returns `false` if the time runs out, and an error if tsgo no longer reads its stdin
// (EPIPE; SIGPIPE is ignored).
fn write_frame(fd int, data []u8, timeout time.Duration) !bool {
	sw := time.new_stopwatch()
	mut off := 0
	for off < data.len {
		remaining := timeout - sw.elapsed()
		if remaining <= 0 {
			return false
		}
		mut pfd := C.pollfd{
			fd:     i32(fd)
			events: i16(C.POLLOUT)
		}
		ready := C.poll(&pfd, 1, i32(remaining / time.millisecond) + 1)
		if ready < 0 && C.errno != C.EINTR {
			return error('poll failed (errno ${C.errno})')
		}
		if ready <= 0 {
			continue
		}
		chunk := if data.len - off < pipe_buf { data.len - off } else { pipe_buf }
		n := C.write(i32(fd), unsafe { &data[off] }, uint(chunk))
		if n < 0 {
			if C.errno == C.EINTR || C.errno == C.EAGAIN {
				continue
			}
			return error('could not write to its stdin (errno ${C.errno})')
		}
		off += int(n)
	}
	return true
}

// adopt_pipes and release_pipes have nothing to do here: V gives the pipes in p.stdio_fd, and
// p.close() closes them.
fn adopt_pipes(mut p os.Process) {}

fn release_pipes(mut p os.Process) {}

fn close_fd(fd int) {
	os.fd_close(fd)
}

// kill_now kills the process. Before V b69f626, `signal_kill()` marked the process as `.aborted`
// and then `wait()` no longer reaped it (it stayed a zombie, vlang/v#29631). With `C.kill`, the
// `wait()` that follows reaps it with any V.
fn kill_now(mut p os.Process) {
	C.kill(i32(p.pid), C.SIGKILL)
}
