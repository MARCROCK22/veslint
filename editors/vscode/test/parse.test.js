'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { parseLine, parseOutput, parseStderr, unescapeField, ruleDocumentation } = require('../lib/parse');

test('a problem with two suggestions', () => {
  const line =
    'base.ts:5:3\t@typescript-eslint/no-floating-promises\tfloatingVoid\tPromises must be awaited.\tsuggestion\tfloatingFixVoid\tAdd void operator to ignore.\t144\t144\tvoid \tsuggestion\tfloatingFixAwait\tAdd await operator.\t144\t144\tawait ';
  assert.deepEqual(parseLine(line), {
    path: 'base.ts',
    line: 5,
    column: 3,
    rule: '@typescript-eslint/no-floating-promises',
    messageId: 'floatingVoid',
    message: 'Promises must be awaited.',
    fix: null,
    suggestions: [
      { messageId: 'floatingFixVoid', message: 'Add void operator to ignore.', start: 144, end: 144, text: 'void ' },
      { messageId: 'floatingFixAwait', message: 'Add await operator.', start: 144, end: 144, text: 'await ' },
    ],
    endLine: null,
    endColumn: null,
  });
});

test('where a problem ends, after its fix and its suggestions', () => {
  const problem = parseLine('a.ts:3:7	no-var	unexpectedVar	Unexpected var, use let or const instead.	fix	32	35	let	end	4	2');
  assert.deepEqual(problem.fix, { start: 32, end: 35, text: 'let' });
  assert.equal(problem.endLine, 4);
  assert.equal(problem.endColumn, 2);
  // A field this version does not know ends the problem, which is still a problem.
  const later = parseLine('a.ts:3:7	no-var	unexpectedVar	m	end	3	9	new	1');
  assert.equal(later.endColumn, 9);
});

test('a problem with a fix whose text is one space, and one without any', () => {
  const fixed = parseLine("base.ts:11:3\teslint\twarning\tUnused eslint-disable directive (no problems were reported).\tfix\t263\t325\t ");
  assert.equal(fixed.rule, 'eslint');
  assert.equal(fixed.messageId, 'warning');
  assert.deepEqual(fixed.fix, { start: 263, end: 325, text: ' ' });
  const plain = parseLine('src/a b:c.ts:12:7\t@typescript-eslint/await-thenable\tawait\tUnexpected `await` of a non-Promise (non-"Thenable") value.');
  assert.equal(plain.path, 'src/a b:c.ts');
  assert.equal(plain.line, 12);
  assert.equal(plain.column, 7);
  assert.equal(plain.fix, null);
  assert.deepEqual(plain.suggestions, []);
});

test('a fix with an empty text, and escaped fields', () => {
  const removed = parseLine('a.ts:1:1\t@typescript-eslint/no-meaningless-void-operator\tmeaninglessVoidOperator\tvoid is useless.\tfix\t0\t5\t');
  assert.deepEqual(removed.fix, { start: 0, end: 5, text: '' });
  const escaped = parseLine('a.ts:1:1\tx\ty\tone\\ntwo\\ttab\\\\slash\tfix\t1\t2\tline\\r\\nnext');
  assert.equal(escaped.message, 'one\ntwo\ttab\\slash');
  assert.equal(escaped.fix.text, 'line\r\nnext');
  assert.equal(unescapeField('a\\\\nb'), 'a\\nb');
});

test('what is not a problem is skipped', () => {
  assert.equal(parseLine(''), null);
  assert.equal(parseLine('12 problems in 3 files'), null);
  assert.equal(parseLine('app.ts:2:7\tsaludo\t"Hola"'), null);
  assert.equal(parseOutput('a.ts:1:1\tr\tm\ttext\n\nnoise\nb.ts:2:3\tr\tm\tmore\n').length, 2);
});

test('standard error: warnings, the summary and errors', () => {
  const said = parseStderr(
    'warning: veslint does not have 5 of the active rules of the configuration and ignores them: no-debugger\n12 problems in 3 files (8 of them warnings)\n',
  );
  assert.deepEqual(said.warnings, ['veslint does not have 5 of the active rules of the configuration and ignores them: no-debugger']);
  assert.equal(said.summary, '12 problems in 3 files (8 of them warnings)');
  assert.deepEqual(said.errors, []);
  const failed = parseStderr('veslint: rules.json: Key "rules": Key "x":\n\tValue 3 is wrong.\n');
  assert.deepEqual(failed.errors, ['rules.json: Key "rules": Key "x":\n\tValue 3 is wrong.']);
});

test('the documentation of a rule', () => {
  assert.equal(ruleDocumentation('@typescript-eslint/await-thenable'), 'https://typescript-eslint.io/rules/await-thenable');
  assert.equal(ruleDocumentation('no-debugger'), 'https://eslint.org/docs/latest/rules/no-debugger');
  assert.equal(ruleDocumentation('seyfert/group-exists'), 'https://github.com/tiramisulabs/extra/tree/main/packages/eslint-plugin/docs/group-exists.md');
  assert.equal(ruleDocumentation('unicorn/no-null'), null);
  assert.equal(ruleDocumentation('eslint'), null);
});
