#!/usr/bin/env node
// Runs the veslint binary of this platform, which npm installs with the optional dependency
// @marcrock22/veslint-<platform>-<arch>, with the same arguments, stdio and exit code.
'use strict';

const { spawn } = require('node:child_process');
const path = require('node:path');

const name = `@marcrock22/veslint-${process.platform}-${process.arch}`;
const exe = process.platform === 'win32' ? 'veslint.exe' : 'veslint';

let bin;
try {
	bin = path.join(path.dirname(require.resolve(`${name}/package.json`)), exe);
} catch {
	console.error(`veslint: the package ${name} is not installed. veslint runs on Linux x64 (glibc) and Windows x64; on those, install @marcrock22/veslint again without omitting its optional dependencies.`);
	process.exit(1);
}

const child = spawn(bin, process.argv.slice(2), { stdio: 'inherit' });
// A signal for this process is one for veslint too (the terminal sends Ctrl+C to both).
const signals = ['SIGINT', 'SIGTERM', 'SIGHUP'];
for (const signal of signals) {
	process.on(signal, () => child.kill(signal));
}
child.on('error', (error) => {
	console.error(`veslint: could not run ${bin}: ${error.message}`);
	process.exit(1);
});
child.on('exit', (code, signal) => {
	if (signal) {
		// End as veslint ended, by the same signal.
		for (const each of signals) {
			process.removeAllListeners(each);
		}
		process.kill(process.pid, signal);
		return;
	}
	process.exit(code ?? 1);
});
