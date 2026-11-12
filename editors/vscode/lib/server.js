'use strict';
// A long-lived `veslint --server` (see server.v in the repository): it keeps the TypeScript
// compiler and the project of a folder between requests. One JSON request per line on its stdin,
// one JSON answer per line on its stdout, in order; each answer has the `stdout`, `stderr` and
// `code` a run of the command line would have. Nothing here needs VS Code.
const { spawn } = require('node:child_process');

class ServerError extends Error {
  constructor(message, code) {
    super(message);
    this.code = code;
  }
}

class VeslintServer {
  /**
   * @param {string} binary the veslint binary
   * @param {string} cwd the folder the server runs in (relative paths of requests are relative to it)
   * @param {{ timeout?: number }} options
   */
  constructor(binary, cwd, options = {}) {
    this.binary = binary;
    this.cwd = cwd;
    this.timeout = options.timeout ?? 120000;
    this.child = null;
    this.pending = [];
    this.buffer = '';
    this.stderr = '';
    this.nextId = 1;
    this.answered = false;
  }

  get running() {
    return this.child !== null;
  }

  start() {
    if (this.child) return;
    const child = spawn(this.binary, ['--server'], { cwd: this.cwd, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child = child;
    this.buffer = '';
    this.stderr = '';
    this.answered = false;
    child.stdout.setEncoding('utf8').on('data', chunk => this.receive(chunk));
    // Its last lines, for the error when it stops.
    child.stderr.setEncoding('utf8').on('data', chunk => (this.stderr = (this.stderr + chunk).slice(-4096)));
    // A write to a server that died fails here and in `close`.
    child.stdin.on('error', () => {});
    // The binary cannot be run (it is not there, or not executable).
    child.on('error', error => {
      if (this.child === child) this.child = null;
      child.kill('SIGKILL');
      this.fail(error);
    });
    child.on('close', code => {
      if (this.child !== child) return;
      this.child = null;
      // A binary from before the server mode stops at once with a usage error.
      const unsupported = !this.answered && code === 2 && /unknown option|usage:/.test(this.stderr);
      this.fail(
        unsupported
          ? new ServerError(`${this.binary} has no server mode`, 'UNSUPPORTED')
          : new ServerError(`the veslint server stopped (code ${code}): ${this.stderr.trim().split('\n').pop() ?? ''}`, 'EXITED'),
      );
    });
  }

  receive(chunk) {
    this.buffer += chunk;
    for (let end = this.buffer.indexOf('\n'); end >= 0; end = this.buffer.indexOf('\n')) {
      const line = this.buffer.slice(0, end);
      this.buffer = this.buffer.slice(end + 1);
      if (line.trim() === '') continue;
      let answer;
      try {
        answer = JSON.parse(line);
      } catch {
        this.kill(new ServerError(`the veslint server answered something that is not JSON: ${line.slice(0, 200)}`, 'PROTOCOL'));
        return;
      }
      this.answered = true;
      const waiting = this.pending.shift();
      if (!waiting) continue;
      clearTimeout(waiting.timer);
      if (answer.id !== waiting.id && answer.id !== -1) {
        waiting.reject(new ServerError(`the veslint server answered request ${answer.id} instead of ${waiting.id}`, 'PROTOCOL'));
        this.kill(new ServerError('the veslint server lost the order of its answers', 'PROTOCOL'));
        return;
      }
      waiting.resolve(answer);
    }
  }

  fail(error) {
    const pending = this.pending;
    this.pending = [];
    for (const waiting of pending) {
      clearTimeout(waiting.timer);
      waiting.reject(error);
    }
  }

  kill(error) {
    const child = this.child;
    this.child = null;
    this.fail(error);
    child?.kill('SIGKILL');
  }

  /**
   * Sends a request and waits for its answer.
   * @returns {Promise<{ id: number, code: number, stdout: string, stderr: string }>}
   */
  request(request) {
    this.start();
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(
        () => this.kill(new ServerError(`no answer in ${this.timeout / 1000} s: the veslint server was stopped`, 'TIMEOUT')),
        this.timeout,
      );
      this.pending.push({ id, resolve, reject, timer });
      this.child.stdin.write(JSON.stringify({ ...request, id }) + '\n');
    });
  }

  /** Ends the server: its stdin closes, and it is killed if it has not ended in two seconds. */
  stop() {
    const child = this.child;
    if (!child) return;
    this.child = null;
    this.fail(new ServerError('the veslint server was stopped', 'STOPPED'));
    child.stdin.end();
    const timer = setTimeout(() => child.kill('SIGKILL'), 2000);
    child.on('close', () => clearTimeout(timer));
  }
}

module.exports = { VeslintServer, ServerError };
