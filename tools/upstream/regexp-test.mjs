// Stands in for eslint-snapshot-rule-tester 0.1.0 while tools/gen_upstream_cases.mjs loads the test
// files of eslint-plugin-regexp v3.3.3: `SnapshotRuleTester#run` records the rule's cases instead of
// running them. The expectation of an invalid case is its entry in
// tests/lib/rules/__snapshots__/<rule>.ts.eslintsnap: readSnapshot reads that file and
// snapshotTitles gives the key of each case, as the package does (src/snapshot/file.ts and
// src/rule-tester.ts), and formatReport writes a lint's problems the way its format.ts does, so that
// the generator can check that what ESLint gives is the snapshot, byte for byte. The code below
// ports those parts of eslint-snapshot-rule-tester (MIT).
export const recorded = (globalThis.__veslintRecorded ??= []);

export class SnapshotRuleTester {
  constructor(config = {}) {
    this.config = config;
  }

  run(name, rule, tests) {
    recorded.push({ name, rule, config: this.config, tests, messages: rule?.meta?.messages ?? {}, mode: 'regexp-snapshot' });
  }
}

const splitLines = s => s.split(/\r?\n/);

// sanitize of src/util.ts: the title of a test.
const sanitize = text =>
  typeof text !== 'string' ? '' : text.replace(/[\u0000-\u0009\u000b-\u001a]/gu, c => `\\u${c.codePointAt(0).toString(16).padStart(4, '0')}`);

// The titles of the invalid cases of a run, in order (`<title> 2` for a title seen before).
export function snapshotTitles(invalid) {
  const known = new Set();
  return invalid.map(item => {
    const test = typeof item === 'string' ? { code: item } : item;
    let title = sanitize(test.name || test.code);
    if (known.has(title)) {
      for (let i = 2; ; ++i) {
        if (!known.has(`${title} ${i}`)) {
          title = `${title} ${i}`;
          break;
        }
      }
    }
    known.add(title);
    return title;
  });
}

function parseKeyLine(line) {
  const consumePart = () => {
    const jsonMatch = /^"(?:[^"\\]|\\.)*"/.exec(line);
    let part;
    if (jsonMatch) {
      part = JSON.parse(jsonMatch[0]);
      line = line.slice(jsonMatch[0].length);
    } else {
      if (/^\s/.test(line)) throw new SyntaxError('Invalid key line: should not start with whitespace');
      const delimiter = line.indexOf(' >>');
      if (delimiter === -1) {
        part = line;
        line = '';
      } else {
        part = line.slice(0, delimiter);
        line = line.slice(delimiter);
      }
    }
    return part;
  };
  const parts = [];
  let includesCode = false;
  for (;;) {
    parts.push(consumePart());
    if (line === '') break;
    else if (line.startsWith(' >> ')) line = line.slice(4);
    else if (line.startsWith(' >>> ')) {
      line = line.slice(5);
      includesCode = true;
    }
  }
  return { parts, includesCode };
}

function parseCodeSection(content) {
  const sectionMatch = /^Code:\n((?: *(?:\d+ )?\|[^\n]*\n)+)/m.exec(content);
  if (sectionMatch === null) return undefined;
  return splitLines(sectionMatch[1])
    .filter(l => /^ *\d/.test(l))
    .map(l => l.replace(/^ *\d+ \| ?/, ''))
    .join('\n');
}

const V1_PREFIX = '# eslint-snapshot-rule-tester format: v1\n';

// The entries of a snapshot file: a Map from the JSON of the key's parts ([rule, 'invalid', title])
// to the value.
export function readSnapshot(content, file) {
  content = content.replace(/\r\n/g, '\n');
  if (!content.startsWith(V1_PREFIX)) throw new SyntaxError(`Snapshot file ${file} is not in the expected format`);
  content = content.slice(V1_PREFIX.length).replace(/^\n+/, '');
  const parsed = new Map();
  while (content !== '') {
    const lineEnd = content.indexOf('\n');
    if (lineEnd === -1) throw new SyntaxError(`Unexpected EOF when reading key: ${content}\nFile: ${file}`);
    let keyLine = content.slice(0, lineEnd);
    if (!keyLine.startsWith('Test: ')) throw new SyntaxError(`Expected key line, got: ${keyLine}\nFile: ${file}`);
    keyLine = keyLine.slice(6);
    const key = parseKeyLine(keyLine);
    content = content.slice(lineEnd + 1);
    const valueMatch = /^(?:[\s\S]*?\n)??---(?=\n|$)/.exec(content);
    if (valueMatch === null) throw new SyntaxError(`Unable to parse value for key: ${keyLine}\nFile: ${file}`);
    const formattedValue = valueMatch[0];
    let value = formattedValue.slice(0, -4);
    if (/^"/m.test(value)) {
      value = splitLines(value)
        .map(l => (l.startsWith('"') ? JSON.parse(l) : l))
        .join('\n');
    }
    content = content.slice(formattedValue.length);
    if (!key.includesCode) {
      const code = parseCodeSection(value);
      if (code === undefined) throw new SyntaxError(`Expected code section for key without code: ${keyLine}\nFile: ${file}`);
      key.parts.push(code);
    }
    parsed.set(JSON.stringify(key.parts), value);
    content = content.replace(/^\n+/, '');
  }
  return parsed;
}

// format of src/format.ts without its first part (the YAML of the case's other keys): the code with
// the places of the problems, the output of the fixes and the problems with their suggestions.
export function formatReport(test, fixable, output, messages) {
  let result = '';
  result += formatCode(test, messages);
  result += formatOutput(output, fixable);
  result += formatMessages(test, messages);
  return result.replace(/\r\n/g, '\n').replace(/\n{0,3}$/, '');
}

function groupByLine(codeLines, messages) {
  const locations = messages
    .map((message, i) => ({
      line: message.line,
      column: message.column,
      endLine: message.endLine ?? message.line,
      endColumn: message.endColumn ?? message.column + 1,
      messageIndex: i,
    }))
    .sort((a, b) => a.line - b.line || a.column - b.column || b.endLine - a.endLine || b.endColumn - a.endColumn);
  function decodeLoc(loc, line, length) {
    let start, startContinued, end, endContinued;
    if (loc.line < line) {
      start = 0;
      startContinued = true;
    } else {
      start = loc.column - 1;
      startContinued = false;
    }
    if (loc.endLine > line) {
      end = length;
      endContinued = true;
    } else {
      end = loc.endColumn - 1;
      endContinued = false;
    }
    return { start, startContinued, end, endContinued, messageIndex: loc.messageIndex };
  }
  const byLines = new Map();
  for (const loc of locations) {
    for (let line = loc.line; line <= loc.endLine; line++) {
      const list = byLines.get(line) ?? [];
      const lineLength = codeLines.at(line - 1)?.length ?? 0;
      list.push(decodeLoc(loc, line, lineLength));
      byLines.set(line, list);
    }
  }
  return byLines;
}

const ERROR_LINE_PREFIX = '    |';

function standardFormatLocations(locations, offset) {
  const locLines = [];
  for (const loc of locations) {
    const { start, startContinued, end, endContinued, messageIndex } = loc;
    const content =
      (startContinued ? '~' : '^') + '~'.repeat(Math.max(0, end - start - 1)) + (endContinued ? `\\ [${messageIndex + 1}] ` : ` [${messageIndex + 1}] `);
    const locLineIndex = offset + start;
    let added = false;
    for (let i = 0; i < locLines.length; i++) {
      const line = locLines[i];
      if (line.length <= locLineIndex) {
        locLines[i] = line.padEnd(locLineIndex) + content;
        added = true;
        break;
      }
    }
    if (!added) locLines.push(ERROR_LINE_PREFIX.padEnd(locLineIndex) + content);
  }
  return locLines;
}

function compactFormatLocations(locations, offset) {
  let squiggleLine = '';
  let messageLine = '';
  for (const [index, loc] of locations.entries()) {
    const nextLoc = locations.at(index + 1);
    const { start, startContinued, end, endContinued, messageIndex } = loc;
    if (startContinued || endContinued) return undefined;
    const squiggle = '^' + '~'.repeat(Math.max(0, end - start - 1));
    const num = `[${messageIndex + 1}]`;
    const unindentNum = nextLoc && nextLoc.start === start + num.length;
    if (squiggleLine.length <= start) squiggleLine = squiggleLine.padEnd(start) + squiggle + ' ';
    else return undefined;
    if (unindentNum && messageLine.length <= start - 1) messageLine = messageLine.padEnd(start - 1) + num + ' ';
    else if (messageLine.length <= start) messageLine = messageLine.padEnd(start) + num + ' ';
    else return undefined;
  }
  const prefix = ERROR_LINE_PREFIX.padEnd(offset);
  return [prefix + squiggleLine, prefix + messageLine];
}

function formatCode(test, messages) {
  const codeLines = splitLines(test.code);
  const byLines = groupByLine(codeLines, messages);
  const outputLines = [];
  codeLines.forEach((codeLine, lineIndex) => {
    const prefix = String(lineIndex + 1).padStart(3) + ' | ';
    const offset = prefix.length;
    outputLines.push(codeLine === '' ? prefix.trimEnd() : prefix + codeLine);
    const locations = byLines.get(lineIndex + 1) ?? [];
    let locLines = standardFormatLocations(locations, offset);
    if (locLines.length >= 2) {
      const compact = compactFormatLocations(locations, offset);
      if (compact) locLines = compact;
    }
    outputLines.push(...locLines.map(l => l.trimEnd()));
  });
  return 'Code:\n' + outputLines.join('\n') + '\n\n';
}

function formatOutputCode(code) {
  return splitLines(code).map((l, i) => {
    const p = String(i + 1).padStart(3) + ' | ';
    return l === '' ? p.trimEnd() : p + l;
  });
}

function formatOutput(output, fixable) {
  if (output === undefined) return fixable ? 'Output: unchanged\n\n' : '';
  return `Output:\n${formatOutputCode(output).join('\n')}\n\n`;
}

function indentLines(lines, indent) {
  const i = ' '.repeat(indent);
  return lines.map(line => (line === '' ? '' : i + line));
}

function formatSuggestions({ code }, suggestions) {
  const result = ['Suggestions:'];
  const firstPrefix = '  - ';
  const prefix = '    ';
  for (const { desc, fix } of suggestions) {
    const messageLines = splitLines(desc);
    result.push(firstPrefix + messageLines[0]);
    for (const line of messageLines.slice(1)) result.push(prefix + line);
    result.push(prefix + 'Output:');
    const output = code.slice(0, fix.range[0]) + fix.text + code.slice(fix.range[1]);
    result.push(...indentLines(formatOutputCode(output), prefix.length));
  }
  return result;
}

function formatMessages(test, messages) {
  if (messages.length === 0) return 'No errors\n';
  return (
    messages
      .flatMap(({ message, suggestions }, i) => {
        const prefix = `[${i + 1}] `;
        const space = ' '.repeat(prefix.length);
        const lines = splitLines(message).map((l, j) => (j === 0 ? prefix + l : space + l));
        if (suggestions) lines.push(...indentLines(formatSuggestions(test, suggestions), space.length));
        return lines;
      })
      .join('\n') + '\n'
  );
}
