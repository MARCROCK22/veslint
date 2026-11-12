// cross_eslint.mjs CONFIG FILE...: lints each file on its own with ESLint's API, so that a rule
// that throws on one file only loses that file. Prints ESLint's JSON results; a file a rule threw
// on has one fatal message with the rule `crash`.
import { createRequire } from 'node:module';
import path from 'node:path';
const require = createRequire(path.resolve('build/eval/spider-byte/node_modules/eslint/package.json'));
const { ESLint } = require('eslint');
const [config, ...files] = process.argv.slice(2);
const eslint = new ESLint({ overrideConfigFile: config });
const results = [];
for (const file of files) {
  try {
    results.push(...(await eslint.lintFiles([file])));
  } catch (error) {
    const message = String(error?.message ?? error).split('\n')[0];
    const rule = /Rule: "([^"]+)"/.exec(String(error?.message ?? ''))?.[1] ?? 'unknown';
    results.push({ filePath: path.resolve(file), messages: [{ ruleId: 'crash', fatal: true, severity: 2, line: 0, column: 0, message: `${rule}: ${message}` }] });
  }
}
process.stdout.write(JSON.stringify(results));
