module main

import os

// cpus_allowed_list is the Cpus_allowed_list line of a /proc status file.
fn cpus_allowed_list(status string) string {
	for line in status.split_into_lines() {
		if line.starts_with('Cpus_allowed_list:') {
			return line.all_after(':').trim_space()
		}
	}
	return ''
}

fn wait_for(ch chan bool) {
	_ := <-ch
}

// It restricts this process (a test file of its own, so nothing runs after it in it): every
// thread, the ones started before too, and the processes started after it.
fn test_limit_cpus_restricts_every_thread_and_the_children() {
	allowed := allowed_cpus() or { panic(err) }
	if allowed.len < 2 {
		eprintln('skipped: this process may only use one CPU')
		return
	}
	limit_cpus(0)
	assert allowed_cpus()! == allowed
	ch := chan bool{}
	waiter := spawn wait_for(ch)
	limit_cpus(1)
	only := allowed_cpus()!
	assert only.len == 1
	assert only[0] in allowed
	tasks := os.ls('/proc/self/task') or { panic(err) }
	assert tasks.len >= 2
	for task in tasks {
		status := os.read_file('/proc/self/task/${task}/status') or { continue }
		assert cpus_allowed_list(status) == '${only[0]}', 'thread ${task}'
	}
	child := os.exec(['cat', '/proc/self/status'])
	assert child.exit_code == 0
	assert cpus_allowed_list(child.output) == '${only[0]}'
	ch <- true
	waiter.wait()
}
