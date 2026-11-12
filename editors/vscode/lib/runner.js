'use strict';
// Runs the veslint binary on files and returns what it reported. Nothing here needs VS Code.
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const { parseOutput, parseStderr } = require('./parse');

const configNames = ['js', 'mjs', 'cjs', 'ts', 'mts', 'cts'].map(extension => `eslint.config.${extension}`);
const typescriptExtensions = ['.ts', '.mts', '.cts', '.tsx'];

/** veslint only reads TypeScript files. */
function isTypeScriptPath(file) {
  return typescriptExtensions.includes(path.extname(file).toLowerCase());
}

/**
 * The configuration for the files of `folder`: the one of the settings (relative to the folder
 * when it is not absolute) or the ESLint configuration at the root of the folder; null without
 * either.
 */
function findConfig(folder, setting) {
  if (setting) {
    const file = path.isAbsolute(setting) ? setting : path.join(folder, setting);
    return fs.existsSync(file) ? file : null;
  }
  for (const name of configNames) {
    const file = path.join(folder, name);
    if (fs.existsSync(file)) return file;
  }
  return null;
}

/**
 * Runs the veslint binary with `args` in `cwd` and collects what it prints. A run that takes more
 * than `timeout` milliseconds, or whose `signal` is aborted, is killed.
 *
 * @param {string} binary
 * @param {string[]} args
 * @param {{ cwd: string, timeout?: number, signal?: AbortSignal }} options
 * @returns {Promise<{ code: number | null, stdout: string, stderr: string, cancelled: boolean, timedOut: boolean }>}
 */
function spawnVeslint(binary, args, options) {
  const timeout = options.timeout ?? 120000;
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { cwd: options.cwd, stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    let cancelled = false;
    let timedOut = false;
    const stop = () => {
      cancelled = true;
      child.kill('SIGKILL');
    };
    const timer = setTimeout(() => {
      timedOut = true;
      stop();
    }, timeout);
    options.signal?.addEventListener('abort', stop, { once: true });
    child.stdout.setEncoding('utf8').on('data', chunk => (stdout += chunk));
    child.stderr.setEncoding('utf8').on('data', chunk => (stderr += chunk));
    child.on('error', error => {
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', stop);
      reject(error);
    });
    child.on('close', code => {
      clearTimeout(timer);
      options.signal?.removeEventListener('abort', stop);
      resolve({ code, stdout, stderr, cancelled: cancelled && !timedOut, timedOut });
    });
  });
}

/** The arguments of a file: relative to the directory veslint runs in, as a user would type them. */
function fileArgs(cwd, files) {
  return files.map(file => path.relative(cwd, file) || file);
}

/**
 * Runs veslint in `cwd`, which is the directory the patterns of an ESLint configuration are
 * relative to (as with `eslint -c`).
 *
 * @param {{ binary: string, cwd: string, config: string, files: string[], project?: string, timeout?: number, signal?: AbortSignal }} options
 * @returns {Promise<{ code: number | null, problems: ReturnType<typeof parseOutput>, warnings: string[], errors: string[], summary: string, cancelled: boolean }>}
 */
async function runVeslint(options) {
  const args = ['--config', options.config, '--fixes'];
  if (options.project) args.push('--project', options.project);
  args.push(...fileArgs(options.cwd, options.files));
  const run = await spawnVeslint(options.binary, args, options);
  const said = parseStderr(run.stderr);
  if (run.timedOut) said.errors.push(`no answer in ${(options.timeout ?? 120000) / 1000} s: the run was stopped`);
  return { code: run.code, problems: parseOutput(run.stdout), ...said, cancelled: run.cancelled };
}

/**
 * The configuration ESLint resolves for each file, as `veslint --print-config` prints it: one
 * call, so ESLint is started once for all of them.
 *
 * @param {{ binary: string, cwd: string, config: string, files: string[], timeout?: number, signal?: AbortSignal }} options
 * @returns {Promise<{ resolved: object | null, errors: string[], cancelled: boolean }>}
 */
async function printConfig(options) {
  const args = ['--config', options.config, '--print-config', ...fileArgs(options.cwd, options.files)];
  const run = await spawnVeslint(options.binary, args, options);
  const said = parseStderr(run.stderr);
  if (run.timedOut) said.errors.push(`no answer in ${(options.timeout ?? 120000) / 1000} s: the run was stopped`);
  if (run.code !== 0 || run.cancelled || said.errors.length > 0) return { resolved: null, errors: said.errors, cancelled: run.cancelled };
  try {
    return { resolved: JSON.parse(run.stdout), errors: [], cancelled: false };
  } catch (error) {
    return { resolved: null, errors: [`the resolved configuration is not JSON: ${error.message}`], cancelled: false };
  }
}

/**
 * Splits a resolved configuration into one per file. The paths veslint prints are relative to
 * the directory of the ESLint configuration; here they become absolute, so that the copy of a
 * file can be kept anywhere. A configuration ESLint did not take (`error`) gives nothing.
 *
 * @returns {Map<string, string>} the JSON text of each file, by its absolute path
 */
function splitResolved(resolved, configFile) {
  const byFile = new Map();
  if (!resolved || typeof resolved !== 'object' || 'error' in resolved || !Array.isArray(resolved.files)) return byFile;
  const base = path.dirname(configFile);
  for (const entry of resolved.files) {
    if (!entry || typeof entry.path !== 'string') continue;
    const file = path.isAbsolute(entry.path) ? entry.path : path.resolve(base, entry.path);
    byFile.set(file, JSON.stringify({ ...resolved, files: [{ ...entry, path: file }] }));
  }
  return byFile;
}

module.exports = { runVeslint, printConfig, splitResolved, spawnVeslint, findConfig, isTypeScriptPath, configNames };
