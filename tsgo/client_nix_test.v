module tsgo

import os
import time

// The tests of the processes the client starts, with the fake tsgo of tests/fake_tsgo.sh and the
// POSIX process calls; on Windows the robustness tests of tests/run.sh cover them with
// tests/fake_tsgo.v.

// A tsgo that ignores stdin being closed forces SIGKILL: shutdown() must finish and reap the
// process, without leaving a zombie.
fn test_shutdown_kills_and_reaps_a_process_that_ignores_stdin() {
	dir := os.join_path(os.temp_dir(), 'veslint-test-${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	fake := os.join_path(@VMODROOT, 'tests', 'fake_tsgo.sh')
	wrapper := os.join_path(dir, 'tsc')
	os.write_file(wrapper, '#!/usr/bin/env bash\nexec "${fake}" silent "$@"\n') or { panic(err) }
	os.chmod(wrapper, 0o755) or { panic(err) }
	mut client := start(wrapper, dir, 5 * time.second) or { panic(err) }
	pid := client.proc.pid
	sw := time.new_stopwatch()
	client.shutdown()
	assert sw.elapsed() < 5 * time.second
	assert !os.exists('/proc/${pid}')
}

// The version check has the timeout of a request: start() fails, without hanging, with a binary
// that never answers `--version` and with one that answers and does not exit, and the binary is
// killed and reaped.
fn test_version_check_times_out() {
	check_version_timeout('version-hang')
	check_version_timeout('version-linger')
}

fn check_version_timeout(mode string) {
	tag := 'vtest-${os.getpid()}'
	dir := os.join_path(os.temp_dir(), 'veslint-test-${os.getpid()}-${mode}')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	fake := os.join_path(@VMODROOT, 'tests', 'fake_tsgo.sh')
	wrapper := os.join_path(dir, 'tsc')
	os.write_file(wrapper, '#!/usr/bin/env bash\nFAKE_TSGO_TAG=${tag} exec "${fake}" ${mode} "$@"\n') or {
		panic(err)
	}
	os.chmod(wrapper, 0o755) or { panic(err) }
	sw := time.new_stopwatch()
	mut message := ''
	if mut client := start(wrapper, dir, 300 * time.millisecond) {
		client.shutdown()
	} else {
		message = err.msg()
	}
	assert message.contains('timeout: `${wrapper} --version` did not finish within'), '${mode}: ${message}'
	assert sw.elapsed() < 5 * time.second
	// The fake binary renames itself `fake-tsgo-<tag>-version` while it waits.
	assert os.exec(['pgrep', '-f', '^fake-tsgo-${tag}-']).exit_code == 1, '${mode}: the binary is still running'
	// And it was reaped: this process has no child left, running or zombie.
	mut status := 0
	assert C.waitpid(-1, &status, C.WNOHANG) == -1, '${mode}: a child was left'
}

// What the version check reads: the text of both outputs and the exit code.
fn test_version_output() {
	dir := os.join_path(os.temp_dir(), 'veslint-test-${os.getpid()}-version')
	os.mkdir_all(dir) or { panic(err) }
	defer {
		os.rmdir_all(dir) or {}
	}
	script := os.join_path(dir, 'tsc')
	os.write_file(script, '#!/usr/bin/env bash\necho "to stdout"\necho "to stderr" >&2\nexit 3\n') or {
		panic(err)
	}
	os.chmod(script, 0o755) or { panic(err) }
	output, code := version_output(script, 5 * time.second) or { panic(err) }
	assert output == 'to stdout\nto stderr\n'
	assert code == 3
	// The pinned binary answers its version.
	real := os.join_path(@VMODROOT, rel_path)
	if os.is_executable(real) {
		real_output, real_code := version_output(real, 5 * time.second) or { panic(err) }
		assert real_output.trim_space() == required_version
		assert real_code == 0
	}
}
