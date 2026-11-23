module main

import os
import time

// --fix writes each pass of a file to disk, where tsgo reads it (Worker.lint), so a file with
// fixes is written up to ten times in a row. On Windows another process may have the file open
// for a moment after veslint wrote it (an antivirus scanning it, the search indexer, a file
// watcher), without sharing it for writing: the next open fails with a sharing violation, which
// the C runtime gives as EACCES. FixWriter then tries again for a while, as graceful-fs tries a
// rename again for up to a minute on Windows (EACCES, EPERM, EBUSY). The file is written in place,
// as before and as ESLint's `fs.writeFile`, so it keeps what it is (its permissions, owner, ACL,
// hard links, the target of a symbolic link) and no other file is ever made; every attempt writes
// the whole text again, so one cut short is mended by the next.

// fix_write_limit is how long a write that fails for a reason that may pass is tried again.
const fix_write_limit = 60 * time.second

// FixWriter writes the files --fix fixes. VESLINT_DEBUG_WRITE_FAILURES=<n>[@<file name>] makes
// the first n attempts to write a file (one of that name, when given) fail as a sharing violation
// does, and VESLINT_DEBUG_WRITE_LIMIT_MS=<ms> sets how long a write is tried again: tests/run.sh
// takes them, as no other process holds files there.
struct FixWriter {
mut:
	injected      int
	injected_name string
	limit         time.Duration = fix_write_limit
}

fn new_fix_writer() FixWriter {
	mut w := FixWriter{}
	failures := os.getenv('VESLINT_DEBUG_WRITE_FAILURES')
	if failures != '' {
		w.injected = failures.all_before('@').int()
		if failures.contains('@') {
			w.injected_name = failures.all_after('@')
		}
	}
	limit := os.getenv('VESLINT_DEBUG_WRITE_LIMIT_MS')
	if limit != '' {
		w.limit = limit.int() * time.millisecond
	}
	return w
}

// write writes `text` over the file at `path`, trying again with a growing pause (10 ms, doubled
// up to 500 ms) while the failure may pass, for up to `limit`; the error says how long it tried.
fn (mut w FixWriter) write(path string, text string) ! {
	sw := time.new_stopwatch()
	mut pause := 10 * time.millisecond
	mut attempts := 0
	for {
		attempts++
		w.write_once(path, text) or {
			if !may_pass(err.code(), path) || sw.elapsed() + pause > w.limit {
				if attempts == 1 {
					return err
				}
				return error('${err.msg()}, ${attempts} attempts in ${f64(sw.elapsed()) / f64(time.second):.1f} s')
			}
			time.sleep(pause)
			if pause < 500 * time.millisecond {
				pause *= 2
			}
			continue
		}
		return
	}
}

fn (mut w FixWriter) write_once(path string, text string) ! {
	if w.injected > 0 && (w.injected_name == '' || os.file_name(path) == w.injected_name) {
		w.injected--
		return error_with_code('failed to open file "${path}" (VESLINT_DEBUG_WRITE_FAILURES)',
			injected_violation)
	}
	os.write_file(path, text)!
}

// injected_violation is the code of a failure VESLINT_DEBUG_WRITE_FAILURES makes, which stands for
// a sharing violation on any system (ERROR_SHARING_VIOLATION is 32).
const injected_violation = -32

// may_pass tells whether a write that failed with that error code may succeed if tried again: on
// Windows, where the C runtime gives EACCES for a sharing or lock violation (another process has
// the file open without sharing it for writing) as for a denied access, EACCES, EPERM (a file
// being deleted) and EBUSY, but not for a read-only file, which _waccess tells and which waiting
// never makes writable; elsewhere only an interrupted call or a busy file.
fn may_pass(code int, path string) bool {
	if code == injected_violation {
		return true
	}
	$if windows {
		return code in [int(C.EACCES), int(C.EPERM), int(C.EBUSY)]
			&& (!os.exists(path) || os.is_writable(path))
	} $else {
		_ = path
		return code in [int(C.EINTR), int(C.EBUSY)]
	}
}
