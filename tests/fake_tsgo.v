// A native fake tsgo for the robustness tests of tests/run.sh on Windows, which cannot run
// tests/fake_tsgo.sh as tsc.exe: the same modes (but `cpus`, a Linux test), compiled to tsc.exe.
// The mode is FAKE_TSGO_MODE or, without it, the text of `fake_tsgo_mode` next to the executable
// (each sandbox of tests/run.sh has its own).
import os
import time

fn bin_header(n int) []u8 {
	return if n < 256 { [u8(0xc4), u8(n)] } else { [u8(0xc5), u8(n >> 8), u8(n & 255)] }
}

// frame writes a [type, method, payload] message in MessagePack, as fake_tsgo.sh does.
fn frame(typ int, method string, payload string) {
	mut b := [u8(0x93), 0xcc, u8(typ)]
	b << bin_header(method.len)
	b << method.bytes()
	b << bin_header(payload.len)
	b << payload.bytes()
	mut out := os.stdout()
	out.write(b) or {}
	out.flush()
}

fn say(line string) {
	mut out := os.stdout()
	out.write_string(line + '\n') or {}
	out.flush()
}

fn drain_stdin() {
	mut input := os.stdin()
	mut buf := []u8{len: 4096}
	for {
		n := input.read(mut buf) or { break }
		if n <= 0 {
			break
		}
	}
}

fn fake_mode() string {
	mode := os.getenv('FAKE_TSGO_MODE')
	if mode != '' {
		return mode
	}
	return (os.read_file(os.join_path(os.dir(os.executable()), 'fake_tsgo_mode')) or { '' }).trim_space()
}

fn main() {
	mode := fake_mode()
	args := os.args[1..]
	if args.len > 0 && args[0] == '--version' {
		match mode {
			'version-mismatch' {
				say('Version 6.0.3')
			}
			'version-hang' {
				// Never answers.
				time.sleep(600 * time.second)
			}
			'version-linger' {
				// Answers, and neither closes its output nor exits.
				say('Version 7.1.0-beta')
				time.sleep(600 * time.second)
			}
			else {
				say('Version 7.1.0-beta')
			}
		}
		exit(0)
	}
	mut cwd := '/'
	for i, a in args {
		if a == '--cwd' && i + 1 < args.len {
			cwd = args[i + 1].replace('\\', '/')
		}
	}
	initialize := '{"caseSensitivity":1,"currentDirectory":"/"}'
	match mode {
		'die-on-start' {
			eprintln('fake-tsgo: simulated failure at startup')
			exit(3)
		}
		'silent' {
			// Never answers and does not care about stdin being closed: forces a kill.
			time.sleep(600 * time.second)
		}
		'no-read' {
			// Answers initialize and createSnapshot without reading anything, and stops reading stdin.
			cfg := '${cwd}/tsconfig.json'
			frame(4, 'initialize', initialize)
			frame(4, 'createSnapshot', '{"snapshot":1,"projects":[{"id":"${cfg}","configFileName":"${cfg}","parsedCommandLine":{"options":{}}}]}')
			time.sleep(600 * time.second)
		}
		'flood' {
			// After the initialize response, floods messages nobody asked for.
			frame(4, 'initialize', initialize)
			for _ in 0 .. 60 {
				frame(4, 'bogus', 'null')
			}
			drain_stdin()
		}
		'wrong-method' {
			frame(4, 'bogus', 'null')
			drain_stdin()
		}
		'no-projects' {
			frame(4, 'initialize', initialize)
			frame(4, 'createSnapshot', '{"snapshot":1,"projects":[]}')
			drain_stdin()
		}
		'callback' {
			frame(6, 'readFile', '{}')
			drain_stdin()
		}
		else {
			eprintln('fake-tsgo: unknown mode: ${mode}')
			exit(2)
		}
	}
}
