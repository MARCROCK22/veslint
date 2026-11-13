// Generates tests/gitignore_cases.json for rules/gitignore_test.v: what the `ignore` package
// (5.3.2, the one ESLint 10.6.0 uses for no-restricted-imports' `group` patterns) answers for a set
// of gitignore patterns and paths. Each case is a list of patterns, the ignorecase flag and, per
// path, whether `ignore({allowRelativePaths: true, ignorecase}).add(patterns).ignores(path)`.
// The patterns are those of no-restricted-imports' tests in ESLint and a set of tricky ones.
// Dev-time only: run `node tools/gen_gitignore_cases.mjs` (it uses the node_modules that
// tests/eval_spider_byte.sh installs).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const root = path.join(import.meta.dirname, '..');
const require = createRequire(path.join(root, 'build/eval/spider-byte/node_modules/'));
const ignore = require('ignore');
const { version } = require('ignore/package.json');

const tricky = [
  '*', '**', '**/foo', 'foo/**', 'foo/**/bar', '/foo', 'foo/', 'foo/*', '*.js', '!*.js', 'a?c',
  '[abc]', '[a-c]x', '[z-a]', '[!a]', '\\!important', '\\#hash', '#comment', 'foo\\ ', 'foo  ',
  'a\\*b', '**/*.min.*', '../foo', './foo', '@scope/*', '@scope/**', '*/legacy/*', '!*/legacy/ok',
  'lodash/*', '!lodash/pick', 'import1/private/*', 'import2/*', '!import2/good', 'foo/../bar',
  'a\\\\b', '[\\]]', 'x[', 'é*', 'FOO', 'Foo/bar', '.hidden', '*.d.ts', 'a/**/', 'a**b', '\\',
];
const paths = [
  'foo', 'foo/bar', 'foo/bar/baz', 'bar/foo', 'a/foo', 'x.js', 'dir/x.js', 'abc', 'a', 'b', 'bx',
  'ax', 'cx', '!important', '#hash', 'foo ', 'a*b', 'axb', 'lib.min.js', 'lodash', 'lodash/pick',
  'lodash/map', '@scope/pkg', '@scope/pkg/sub', 'app/legacy/thing', 'app/legacy/ok',
  'import1/private/x', 'import2/good', 'import2/bad', 'bar', 'a\\b', ']', 'x[', 'éa', 'FOO', 'foo',
  'Foo/bar', 'foo/BAR', '.hidden', 'types.d.ts', 'a/b/c', 'ab', 'aXb', 'a/b', '../foo', './foo',
  'fs', 'os', 'path/to/file', 'some/path', 'some-path',
];

// The group patterns of ESLint's tests (each test's list stays one case).
const source = fs.readFileSync(path.join(root, 'build/upstream/eslint/tests/lib/rules/no-restricted-imports.js'), 'utf8');
const groups = [];
for (const match of source.matchAll(/group:\s*(\[[^\]]*\])/g)) {
  try {
    groups.push(eval(match[1]));
  } catch {}
}
for (const match of source.matchAll(/patterns:\s*(\[\s*(?:"[^"]*"|'[^']*')(?:\s*,\s*(?:"[^"]*"|'[^']*'))*\s*,?\s*\])/g)) {
  try {
    groups.push(eval(match[1]));
  } catch {}
}
const sources = [...source.matchAll(/(?:from|import)\s+["']([^"']+)["']/g)].map(m => m[1]);
const allPaths = [...new Set([...paths, ...sources])];
const lists = [...groups, ...tricky.map(p => [p]), ['*', '!foo'], ['foo/*', '!foo/bar'], ['**/legacy/**', '!**/legacy/ok']];
const cases = [];
for (const patterns of lists) {
  for (const ignorecase of [true, false]) {
    const ig = ignore({ allowRelativePaths: true, ignorecase }).add(patterns);
    cases.push({ patterns, ignorecase, ignored: allPaths.filter(p => ig.ignores(p)) });
  }
}
fs.writeFileSync(path.join(root, 'tests/gitignore_cases.json'), JSON.stringify({ generator: `tools/gen_gitignore_cases.mjs: ignore ${version}`, paths: allPaths, cases }) + '\n');
console.log(`${cases.length} cases, ${allPaths.length} paths`);
