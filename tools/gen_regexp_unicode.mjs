// Generates rules/regexp_unicode.v: the Unicode data rules/regexp_syntax.v needs to decide, like
// V8 (the engine ESLint runs on), whether a regular expression is valid:
// - the names and values `\p{…}` accepts (General_Category and Script/Script_Extensions values,
//   binary properties and, with the `v` flag, properties of strings);
// - the characters a capture group name may start with or contain.
// Node runs this script at development time only; veslint never runs Node. A name or character
// is accepted only if V8 itself accepts it: the candidate names come from the pinned tables of
// @eslint-community/regexpp 4.12.2 and TypeScript 6.0.3 (in the node_modules that
// tests/eval_spider_byte.sh installs), and the group name characters are tested one code point
// at a time.
//
// Usage: node tools/gen_regexp_unicode.mjs > rules/regexp_unicode.v && v fmt -w rules/regexp_unicode.v
import fs from 'node:fs';
import path from 'node:path';

const root = path.join(import.meta.dirname, '..');
const nodeModules = path.join(root, 'build/eval/spider-byte/node_modules');

function pinned(pkg, version) {
  const json = JSON.parse(fs.readFileSync(path.join(nodeModules, pkg, 'package.json'), 'utf8'));
  if (json.version !== version) {
    throw new Error(`${pkg} is ${json.version}, expected ${version}`);
  }
}
pinned('@eslint-community/regexpp', '4.12.2');
pinned('typescript', '6.0.3');

// The string arguments of `new DataSet(…)` assigned to `name` in regexpp.
function regexppNames(source, name) {
  const match = source.match(new RegExp(`const ${name} = new DataSet\\(([^)]*)\\);`));
  if (!match) {
    throw new Error(`regexpp: ${name} not found`);
  }
  return [...match[1].matchAll(/"([^"]*)"/g)].flatMap(m => m[1].split(' ').filter(Boolean));
}

// The names listed in a TypeScript 6 table (`var name = …;`), as quoted strings.
function typescriptNames(source, name) {
  const start = source.indexOf(`var ${name} = `);
  if (start < 0) {
    throw new Error(`typescript: ${name} not found`);
  }
  const end = source.indexOf(';\n', start);
  return [...source.slice(start, end).matchAll(/"([A-Za-z0-9_]+)"/g)].map(m => m[1]);
}

const regexpp = fs.readFileSync(path.join(nodeModules, '@eslint-community/regexpp/index.js'), 'utf8');
const typescript = fs.readFileSync(path.join(nodeModules, 'typescript/lib/typescript.js'), 'utf8');
const candidates = new Set([
  ...regexppNames(regexpp, 'gcValueSets'),
  ...regexppNames(regexpp, 'scValueSets'),
  ...regexppNames(regexpp, 'binPropertySets'),
  ...regexppNames(regexpp, 'binPropertyOfStringsSets'),
  ...typescriptNames(typescript, 'nonBinaryUnicodeProperties'),
  ...typescriptNames(typescript, 'binaryUnicodeProperties'),
  ...typescriptNames(typescript, 'binaryUnicodePropertiesOfStrings'),
  ...typescriptNames(typescript, 'valuesOfNonBinaryUnicodeProperties'),
]);

function accepts(pattern, flags) {
  try {
    new RegExp(pattern, flags);
    return true;
  } catch {
    return false;
  }
}

const sorted = [...candidates].sort();
const lone = sorted.filter(name => accepts(`\\p{${name}}`, 'u'));
const gcValues = sorted.filter(name => accepts(`\\p{General_Category=${name}}`, 'u'));
const scriptValues = sorted.filter(name => accepts(`\\p{Script=${name}}`, 'u'));
const scriptExtensionValues = sorted.filter(name => accepts(`\\p{Script_Extensions=${name}}`, 'u'));
const binaryProperties = lone.filter(name => !gcValues.includes(name));
const stringProperties = sorted.filter(name => !lone.includes(name) && accepts(`\\p{${name}}`, 'v'));
// Checks of the assumptions rules/regexp_syntax.v makes.
for (const [alias, full] of [['gc', 'General_Category'], ['sc', 'Script'], ['scx', 'Script_Extensions']]) {
  for (const name of sorted) {
    if (accepts(`\\p{${alias}=${name}}`, 'u') !== accepts(`\\p{${full}=${name}}`, 'u')) {
      throw new Error(`${alias} and ${full} differ on ${name}`);
    }
  }
}
for (const name of lone) {
  if (!accepts(`\\p{${name}}`, 'v') || !accepts(`\\P{${name}}`, 'u')) {
    throw new Error(`${name} is not accepted with v or negated`);
  }
}
for (const name of sorted) {
  if (accepts(`\\p{${name}=${name}}`, 'u') || accepts(`\\p{Block=${name}}`, 'u')) {
    throw new Error(`unexpected property name in ${name}`);
  }
}

// Inclusive ranges of the code points V8 accepts in a group name, at the start or after it. A
// character counts only if the match's `groups` has exactly the expected name (`(?<!x)` is a
// lookbehind and `(?<a>>x)` names the group `a`). Both the plain and the `u` modes must agree.
function namedGroup(name, flags) {
  try {
    const groups = new RegExp(`(?<${name}>x)`, flags).exec('x')?.groups ?? {};
    const keys = Object.keys(groups);
    return keys.length === 1 && keys[0] === name;
  } catch {
    return false;
  }
}

function groupNameRanges(prefix) {
  const ranges = [];
  for (let cp = 0; cp <= 0x10ffff; cp++) {
    if (cp >= 0xd800 && cp <= 0xdfff) {
      continue;
    }
    const name = prefix + String.fromCodePoint(cp);
    const ok = namedGroup(name, '');
    if (ok !== namedGroup(name, 'u')) {
      throw new Error(`group name character U+${cp.toString(16)} differs with the u flag`);
    }
    if (!ok) {
      continue;
    }
    const last = ranges.at(-1);
    if (last && last[1] === cp - 1) {
      last[1] = cp;
    } else {
      ranges.push([cp, cp]);
    }
  }
  return ranges;
}
const nameStart = groupNameRanges('');
const namePart = groupNameRanges('a');

// Arrays are written on one line: `v fmt -w` wraps them (see Usage).
function stringList(name, comment, values) {
  return `// ${comment}\nconst ${name} = [${values.map(v => `'${v}'`).join(', ')}]`;
}

function rangeList(name, comment, ranges) {
  const items = ranges.flatMap(([a, b]) => [a, b]).map(n => `u32(0x${n.toString(16)})`);
  return `// ${comment}\nconst ${name} = [${items.join(', ')}]`;
}

const out = [
  '// Code generated by tools/gen_regexp_unicode.mjs; DO NOT EDIT.',
  '',
  'module rules',
  '',
  `// Unicode data of the regular expressions of Node ${process.version} (V8 ${process.versions.v8}, ICU ${process.versions.icu}, Unicode ${process.versions.unicode}).`,
  '',
  stringList('regexp_gc_values', 'Values of General_Category (gc), also valid alone: `\\p{L}`.', gcValues),
  '',
  stringList('regexp_script_values', 'Values of Script (sc).', scriptValues),
  '',
  stringList('regexp_script_extensions_values', 'Values of Script_Extensions (scx).', scriptExtensionValues),
  '',
  stringList('regexp_binary_properties', 'Binary properties: `\\p{Alphabetic}`.', binaryProperties),
  '',
  stringList('regexp_string_properties', 'Properties of strings, only with the `v` flag and not negated: `\\p{RGI_Emoji}`.', stringProperties),
  '',
  rangeList('regexp_group_name_start', 'Code points that may start a group name, as inclusive [first, last] pairs.', nameStart),
  '',
  rangeList('regexp_group_name_part', 'Code points that may follow in a group name, as inclusive [first, last] pairs.', namePart),
  '',
];
process.stdout.write(out.join('\n'));
