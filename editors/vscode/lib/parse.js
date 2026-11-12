'use strict';
// The output of `veslint --fixes`: one line per problem, with TAB-separated fields:
//
//   path:line:col  rule  messageId  message  [fix  start  end  text]  [suggestion  messageId  message  start  end  text]...
//
// Lines and columns start at 1 and columns count UTF-16 units, like ESLint's; the ranges of fixes
// and suggestions are offsets in UTF-16 units from the start of the text (without the BOM). In a
// message or a text, a backslash, a line feed, a carriage return and a tab are written `\\`, `\n`,
// `\r` and `\t`. A problem that is not of a rule (a directive comment, a parse error) has the rule
// `eslint` and `fatal`, `error` or `warning` in the place of the messageId.

/** Undoes the escaping of a field. */
function unescapeField(text) {
  return text.replace(/\\(.)/gs, (_, c) => (c === 'n' ? '\n' : c === 'r' ? '\r' : c === 't' ? '\t' : c));
}

/**
 * Parses one line of output; null when the line is not a problem.
 * @param {string} line
 */
function parseLine(line) {
  const fields = line.split('\t');
  if (fields.length < 4) return null;
  const place = /^(.*):(\d+):(\d+)$/.exec(fields[0]);
  if (!place) return null;
  const problem = {
    path: place[1],
    line: Number(place[2]),
    column: Number(place[3]),
    rule: fields[1],
    messageId: fields[2],
    message: unescapeField(fields[3]),
    fix: null,
    suggestions: [],
  };
  let i = 4;
  while (i < fields.length) {
    if (fields[i] === 'fix' && i + 3 < fields.length) {
      problem.fix = { start: Number(fields[i + 1]), end: Number(fields[i + 2]), text: unescapeField(fields[i + 3]) };
      i += 4;
    } else if (fields[i] === 'suggestion' && i + 5 < fields.length) {
      problem.suggestions.push({
        messageId: fields[i + 1],
        message: unescapeField(fields[i + 2]),
        start: Number(fields[i + 3]),
        end: Number(fields[i + 4]),
        text: unescapeField(fields[i + 5]),
      });
      i += 6;
    } else {
      // A field this version does not know: the problem is still a problem.
      break;
    }
  }
  return problem;
}

/** Parses the whole standard output. */
function parseOutput(stdout) {
  const problems = [];
  for (const line of stdout.split('\n')) {
    if (line === '') continue;
    const problem = parseLine(line);
    if (problem) problems.push(problem);
  }
  return problems;
}

/**
 * What veslint says on standard error: `warning: ...` lines, the summary (`N problems in M
 * files`) and, when it could not lint, `veslint: <reason>`.
 */
function parseStderr(stderr) {
  const warnings = [];
  const errors = [];
  let summary = '';
  for (const line of stderr.split('\n')) {
    if (line.startsWith('warning: ')) warnings.push(line.slice('warning: '.length));
    else if (line.startsWith('veslint: ')) errors.push(line.slice('veslint: '.length));
    else if (/^\d+ problems? in \d+ files?/.test(line)) summary = line;
    else if (errors.length > 0 && line !== '') errors[errors.length - 1] += '\n' + line;
  }
  return { warnings, errors, summary };
}

/** The typescript-eslint rules veslint has are documented under this address. */
// The page of a rule, by its ESLint id: typescript-eslint's for `@typescript-eslint/<name>`, the
// one of @slipher/eslint-plugin (its `docs` of `meta`) for `seyfert/<name>`, ESLint's for a rule of
// ESLint core (an id without a plugin); none for a problem without a rule.
function ruleDocumentation(rule) {
  if (rule === 'eslint') return null;
  if (rule.startsWith('@typescript-eslint/')) return `https://typescript-eslint.io/rules/${rule.slice('@typescript-eslint/'.length)}`;
  if (rule.startsWith('seyfert/')) {
    return `https://github.com/tiramisulabs/extra/tree/main/packages/eslint-plugin/docs/${rule.slice('seyfert/'.length)}.md`;
  }
  if (!rule.includes('/')) return `https://eslint.org/docs/latest/rules/${rule}`;
  return null;
}

module.exports = { parseLine, parseOutput, parseStderr, unescapeField, ruleDocumentation };
