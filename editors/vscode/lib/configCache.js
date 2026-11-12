'use strict';
// The configuration of each file, resolved once. An ESLint configuration is JavaScript: veslint
// asks the project's ESLint for it through bun, which takes most of a run. Here it is asked once
// per file (and for every file that needs it at that moment, in one call), kept as the JSON
// `veslint --print-config` prints, and given to veslint in its place until the configuration
// file changes.
const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { printConfig, splitResolved } = require('./runner');

/** The extensions veslint reads as an ESLint configuration (the rest are JSON). */
const eslintConfigExtensions = ['.js', '.mjs', '.cjs', '.ts', '.mts', '.cts'];

function isEslintConfig(file) {
  return eslintConfigExtensions.includes(path.extname(file).toLowerCase());
}

function modified(file) {
  try {
    return fs.statSync(file).mtimeMs;
  } catch {
    return -1;
  }
}

class ConfigCache {
  /** @param {string} directory where the resolved configurations are written */
  constructor(directory) {
    this.directory = directory;
    /** @type {Map<string, { config: string, modified: number, json: string }>} */
    this.entries = new Map();
    /** How many times ESLint was asked: for the tests and the log. */
    this.resolutions = 0;
  }

  /** Whether `file` has a resolved configuration for `config` as it is now. */
  has(file, config) {
    const entry = this.entries.get(file);
    return !!entry && entry.config === config && entry.modified === modified(config) && fs.existsSync(entry.json);
  }

  /**
   * The configuration to give veslint for each of `files`: the resolved copy, or `config` itself
   * when it is not an ESLint configuration or ESLint could not resolve it (then veslint says why).
   * The files that have no copy are resolved together, with one start of ESLint.
   *
   * @param {{ binary: string, cwd: string, config: string, files: string[], timeout?: number, signal?: AbortSignal }} options
   * @returns {Promise<{ configs: Map<string, string>, resolved: number, errors: string[] }>}
   */
  async configsFor(options) {
    const configs = new Map(options.files.map(file => [file, options.config]));
    if (!isEslintConfig(options.config)) return { configs, resolved: 0, errors: [] };
    const missing = options.files.filter(file => !this.has(file, options.config));
    let errors = [];
    if (missing.length > 0) {
      const stamp = modified(options.config);
      this.resolutions++;
      const result = await printConfig({ ...options, files: missing });
      errors = result.errors;
      if (result.resolved) {
        fs.mkdirSync(this.directory, { recursive: true });
        for (const [file, text] of splitResolved(result.resolved, options.config)) {
          const name = crypto.createHash('sha1').update(`${options.config}\0${file}`).digest('hex');
          const json = path.join(this.directory, `${name}.json`);
          fs.writeFileSync(json, text);
          this.entries.set(file, { config: options.config, modified: stamp, json });
        }
      }
    }
    for (const file of options.files) {
      if (this.has(file, options.config)) configs.set(file, this.entries.get(file).json);
    }
    return { configs, resolved: missing.length, errors };
  }

  /** Forgets every resolved configuration, so that the next runs ask ESLint again. */
  clear() {
    for (const entry of this.entries.values()) fs.rmSync(entry.json, { force: true });
    this.entries.clear();
  }
}

module.exports = { ConfigCache, isEslintConfig };
