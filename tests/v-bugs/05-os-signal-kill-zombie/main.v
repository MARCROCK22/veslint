// V bug: os: Process.signal_kill() followed by wait() still leaves a zombie (#20668)
// Reported in vlang/v#29631.
// expected: status=aborted child=reaped

import os
import time

fn main() {
	mut p := os.new_process('/bin/sleep')
	p.set_args(['30'])
	p.run()
	pid := p.pid
	p.signal_kill()
	p.wait()
	time.sleep(300 * time.millisecond)
	stat := os.read_file('/proc/${pid}/stat') or { '' }
	state := if stat == '' { 'reaped' } else { stat.all_after_last(') ').split(' ')[0] }
	println('status=${p.status} child=${state}')
}
