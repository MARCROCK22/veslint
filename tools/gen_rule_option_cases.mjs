// Generates tests/rule_option_cases.json for rules/json_schema_test.v: what ESLint itself says of
// many option values of each ported rule, fitting its schema or not. Each case is given to
// ESLint's Linter twice: as the options of the rule in a configuration (`config`: the message of
// the error it throws, or null) and in the comment `/* eslint rule: [severity, ...options] */`
// (the message it reports, or none; it is in `inline` only when it is not `config` as the linter
// cuts it, which this script checks for every case). The rules
// are stand-ins with the meta of typescript-eslint's (the schema and the default options are all
// ESLint validates with) and a `create` that does nothing, since the real ones need types.
// The values come from the schema of each rule: at every place of it, values of every type, the
// ones the keywords there tell apart, and the options of the fixtures of tests/rules. A second
// part does the same with schemas made for the keywords and the combinations the rules do not
// have, to check the validator itself; and a third has values of a rule that are not a severity
// with options, with what the eslint command prints for them. Dev-time only: run `node tools/gen_rule_option_cases.mjs`
// after tools/gen_rule_schemas.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { portedRules, checkSchema, ruleDefaults, seyfertPlugin, pluginOf } from './rule_schema_support.mjs';

const root = path.resolve(import.meta.dirname, '..');
const modules = path.join(root, 'build/eval/spider-byte/node_modules');
const require = createRequire(path.join(root, 'build/eval/spider-byte/package.json'));
const { Linter } = require('eslint');
const { builtinRules } = require('eslint/use-at-your-own-risk');
const plugin = require('@typescript-eslint/eslint-plugin');
const { Config } = require(path.join(modules, 'eslint/lib/config/config.js'));
const version = name => JSON.parse(fs.readFileSync(path.join(modules, name, 'package.json'), 'utf8')).version;

// ajv warns on the console about a `$ref` with keywords next to it or without a target.
console.warn = () => {};

const linter = new Linter({ configType: 'flat' });
const standIn = rule => ({ meta: rule.meta, create: () => ({}) });

// ask gives ESLint the options of rule `id` of a plugin, with that severity: in a configuration
// and in a configuration comment.
function ask(namespace, rules, id, options, severity) {
  // A rule of ESLint core is the real one (on an empty file it reports nothing).
  const plugins = namespace ? { [namespace]: { rules } } : {};
  const value = [severity, ...options];
  let config = null;
  try {
    linter.verify('', [{ plugins, rules: { [id]: structuredClone(value) } }], { filename: 'a.js' });
  } catch (error) {
    config = error.message;
  }
  // The comment of a case is always this one, so the file does not repeat it.
  const comment = `${id}: ${JSON.stringify(value)}`;
  if (comment.includes('*/') || /\s-{2,}\s/u.test(comment)) {
    throw new Error(`a case cannot be written in a comment: ${comment}`);
  }
  // A rule of ESLint core runs for real: what it reports (with a messageId, as `unicode-bom`
  // "always" on a file without a BOM) is not about the configuration.
  const messages = linter.verify(`/* eslint ${comment} */\n`, [{ plugins }], { filename: 'a.js' }).filter(m => !m.messageId);
  if (messages.length > 1 || (messages.length === 1 && messages[0].ruleId !== id)) {
    throw new Error(`unexpected messages for ${comment}: ${JSON.stringify(messages)}`);
  }
  const inline = messages[0]?.message ?? null;
  // The message of a comment is nearly always the error of the configuration as the linter cuts
  // it: only the ones that are not are written down (`inline`).
  const cut = config === null ? null : `Inline configuration for rule "${id}" is invalid:\n\t${config.slice(`Key "rules": Key "${id}":`.length).trim()}\n`;
  return { ...(severity === 2 ? {} : { severity }), options, config, ...(inline === cut ? {} : { inline }), rejected: inline !== null };
}

// Values of every type, for any place of a schema.
const junk = [null, true, false, 0, 1, -1, 1.5, '', 'x', [], [null], ['x'], {}, { a: 1 }];

function resolve(schema, rootSchema) {
  let current = schema;
  for (let i = 0; i < 16 && current && typeof current === 'object' && typeof current.$ref === 'string'; i++) {
    let target = rootSchema;
    for (const part of current.$ref.split('/').slice(1)) {
      target = target?.[part.replace(/~1/g, '/').replace(/~0/g, '~')];
    }
    if (target === undefined || target === current) {
      return current;
    }
    current = target;
  }
  return current;
}

// fitting is one value that fits the schema (as far as its keywords go).
function fitting(schema, rootSchema, depth = 0) {
  const s = resolve(schema, rootSchema);
  if (typeof s !== 'object' || s === null || depth > 8) {
    return 'x';
  }
  if ('const' in s) return s.const;
  if (s.enum) return s.enum[0];
  for (const key of ['oneOf', 'anyOf', 'allOf']) {
    if (s[key]) return fitting(s[key][0], rootSchema, depth + 1);
  }
  const type = [s.type].flat()[0] ?? (s.properties || s.required ? 'object' : s.items ? 'array' : 'string');
  switch (type) {
    case 'object': {
      const value = {};
      for (const name of s.required ?? []) {
        value[name] = fitting(s.properties?.[name] ?? {}, rootSchema, depth + 1);
      }
      return value;
    }
    case 'array':
      if (Array.isArray(s.items)) {
        return s.items.map(item => fitting(item, rootSchema, depth + 1));
      }
      return Array.from({ length: s.minItems ?? 0 }, () => fitting(s.items ?? {}, rootSchema, depth + 1));
    case 'boolean': return true;
    case 'null': return null;
    case 'number': case 'integer': return 1;
    default: return 'x'.repeat(Math.max(1, s.minLength ?? 1));
  }
}

// samples are the values to try at a schema: the ones of every type, and the ones its keywords tell
// apart, in each of its parts. A schema seen before (the type specifiers are in eight options)
// only gets a few.
const seen = new Set();
function samples(schema, rootSchema, depth = 0) {
  const s = resolve(schema, rootSchema);
  const out = [fitting(schema, rootSchema)];
  if (typeof s !== 'object' || s === null || depth > 6) {
    return [...out, ...junk.slice(0, 4)];
  }
  const key = JSON.stringify(s);
  if (seen.has(key)) {
    return [...out, null, 'x', {}, []];
  }
  seen.add(key);
  out.push(...junk);
  if (s.enum) {
    out.push(...s.enum, 'nope', ['nope']);
  }
  for (const keyword of ['oneOf', 'anyOf', 'allOf']) {
    for (const branch of s[keyword] ?? []) {
      out.push(...samples(branch, rootSchema, depth + 1));
    }
  }
  if (s.not) {
    out.push(...samples(s.not, rootSchema, depth + 1));
  }
  if (s.properties || s.required || s.additionalProperties !== undefined || [s.type].flat().includes('object')) {
    const base = fitting({ ...s, oneOf: undefined, anyOf: undefined, allOf: undefined, enum: undefined, type: 'object' }, rootSchema);
    const full = { ...base };
    for (const [name, sub] of Object.entries(s.properties ?? {})) {
      full[name] = fitting(sub, rootSchema);
      for (const value of samples(sub, rootSchema, depth + 1)) {
        out.push({ ...base, [name]: value });
      }
    }
    out.push(full);
    for (const name of s.required ?? []) {
      const { [name]: _, ...rest } = full;
      out.push(rest);
    }
    out.push({ ...base, nope: 1 }, { also: 2, ...full, nope: 1 }, { b: 3, 10: 1, 2: 2, ...base }, { ...base, __proto__: null });
    out.push(JSON.parse(`{${Object.entries(base).map(([k, v]) => `${JSON.stringify(k)}:${JSON.stringify(v)},`).join('')}"__proto__":1}`));
  }
  if (s.items || s.uniqueItems || s.minItems !== undefined || s.maxItems !== undefined || [s.type].flat().includes('array')) {
    if (Array.isArray(s.items)) {
      const base = s.items.map(item => fitting(item, rootSchema));
      s.items.forEach((item, i) => {
        for (const value of samples(item, rootSchema, depth + 1)) {
          out.push(base.with(i, value));
        }
      });
      out.push(base.slice(0, -1), [...base, 1], [...base, true, 'x']);
    } else {
      const item = fitting(s.items ?? {}, rootSchema);
      for (const value of samples(s.items ?? {}, rootSchema, depth + 1)) {
        out.push([value], [item, value]);
      }
      out.push([], [item], [item, item], [item, item, item]);
    }
    out.push(['a', 'b', 'a'], ['b', 'a', 'a', 'b'], ['a', 'b', 'c', 'b', 'c'], ['__proto__', '__proto__'],
      ['constructor', 'constructor'], ['a', 1, 'a'], [1, '1', 1.0], [{ a: 1 }, { a: 1 }], [[1], [1]], [null, null], [true, 'true', true]);
  }
  if ([s.type].flat().includes('string') || s.minLength !== undefined || s.maxLength !== undefined) {
    out.push('', 'a', 'ab', 'abc', 'abcd', '\u{1F600}', '\u{1F600}\u{1F600}', 'a"b\\.c\n\t\u0001\u007f\u2028é');
  }
  if ([s.type].flat().some(type => type === 'number' || type === 'integer')) {
    out.push(0, -0, 1.0, 1.5, 1e21, 1e-7, 123456789012345680000, 0.1 + 0.2);
  }
  return out;
}

// distinct keeps the first of the values that are the same (by their JSON text).
function distinct(values) {
  const texts = new Set();
  return values.filter(value => {
    const text = JSON.stringify(value);
    if (texts.has(text)) return false;
    texts.add(text);
    return true;
  });
}

// spread keeps `limit` of the values, evenly, and the first `keep` of them.
function spread(values, limit, keep) {
  if (values.length <= limit) {
    return values;
  }
  const rest = values.slice(keep);
  const step = rest.length / (limit - keep);
  return [...values.slice(0, keep), ...Array.from({ length: limit - keep }, (_, i) => rest[Math.floor(i * step)])];
}

// optionLists are the lists of options to try for a schema of options (always an array schema
// here): each place with its samples, and lists that are too short or too long.
function optionLists(schema, first) {
  const lists = [...first];
  if (Array.isArray(schema.items)) {
    const base = schema.items.map(item => fitting(item, schema));
    lists.push([], base);
    schema.items.forEach((item, i) => {
      for (const value of samples(item, schema)) {
        lists.push(base.slice(0, i).concat([value]));
      }
    });
    lists.push([...base, 1], [...base, null, {}]);
  } else {
    lists.push(...samples(schema, schema).filter(Array.isArray));
    lists.push([], [{}], [null], ['x'], [1, 2]);
  }
  return distinct(lists);
}

// The severities of a configuration comment: ESLint validates the options of all but the number 0.
const severities = [2, 'error', 1, 'warn', 0, 'off'];

function casesOf(namespace, rules, id, schema, first, limit) {
  const lists = spread(optionLists(schema, first), limit, first.length + 2);
  const cases = lists.map(options => ask(namespace, rules, id, options, 2));
  // Every severity, for a few lists that fit and a few that do not.
  const invalid = lists.filter((_, i) => cases[i].rejected).slice(0, 3);
  const valid = lists.filter((_, i) => !cases[i].rejected).slice(0, 2);
  for (const options of [...invalid, ...valid]) {
    for (const severity of severities.slice(1)) {
      cases.push(ask(namespace, rules, id, options, severity));
    }
  }
  return cases;
}

// The options of the fixtures: the rules must take them all.
function fixtureOptions(name) {
  const directory = path.join(root, 'tests/rules', name);
  if (!fs.existsSync(directory)) {
    return [];
  }
  return fs.readdirSync(directory, { recursive: true })
    .filter(file => path.basename(file) === 'options.json')
    .sort()
    .map(file => JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8')));
}

// More lists for some rules: the two with meta.defaultOptions, which ESLint merges the options over
// before validating (the value it prints is the merged one), and options with more than one error.
const extra = {
  'dot-notation': [[{ allowKeywords: 5 }], [{ allowPattern: null, nope: 1 }], [null], ['x'], [{}, 1], [[]]],
  'consistent-return': [[{ treatUndefinedAsUnspecified: 'yes' }], [{ nope: 1 }], [null], [{}, {}]],
  'no-floating-promises': [
    [{ ignoreVoid: 'yes', nope: 1 }],
    [{ ignoreVoid: 'yes', ignoreIIFE: 1 }],
    [{ allowForKnownSafeCalls: [{ from: 'file', name: ['a', 'a'] }] }],
    [{ allowForKnownSafeCalls: [{ from: 'package', name: 'a' }] }],
    [{ allowForKnownSafeCalls: [{ from: 'lib', name: 'a', path: 'b' }] }],
    [{ allowForKnownSafeCalls: ['a', { from: 'nope', name: 1 }] }],
    [{ allowForKnownSafeCalls: [{ name: [] }] }],
  ],
  'naming-convention': [
    [{ selector: 'default', format: ['camelCase'] }, { selector: 5, format: null }],
    [{ selector: 'variable', format: ['nope'] }],
    [{ selector: 'variable', format: ['camelCase'], custom: { regex: 'x' } }],
    [{ selector: 'variable', format: ['camelCase'], filter: '' }],
    [{ selector: 'variable', format: ['camelCase'], prefix: [''] }],
    [{ selector: ['variable', 'nope'], format: null }],
    [{ selector: 'variable', format: null, leadingUnderscore: 5 }],
    [{ selector: 'variable', format: null, types: ['nope'] }],
    [{ selector: 'nope', format: null }],
    [{ format: null }],
    [{ selector: 'variable' }],
    ['x'],
  ],
};

const ids = portedRules(root);
const plugins = { '': { rules: Object.fromEntries(builtinRules) }, '@typescript-eslint': plugin, seyfert: seyfertPlugin(root) };
const standIns = {};
for (const id of ids) {
  const [namespace, owner, name] = pluginOf(id, plugins);
  (standIns[namespace] ??= {})[name] = standIn(owner.rules[name]);
}
const schemas = {};
const rules = [];
for (const id of ids) {
  const [namespace, owner, name] = pluginOf(id, plugins);
  const rule = owner.rules[name];
  const schema = Config.getRuleOptionsSchema(rule);
  // A rule of ESLint core is `core/<id>`: dot-notation is both a core and a typescript-eslint name.
  schemas[namespace === '@typescript-eslint' ? name : namespace === '' ? `core/${id}` : id] = schema;
  const first = [...(rule.defaultOptions ? [rule.defaultOptions] : []), ...fixtureOptions(namespace === '@typescript-eslint' ? `@typescript-eslint/${name}` : id), ...(extra[name] ?? [])];
  const limit = name === 'naming-convention' ? first.length + 90 : 600;
  // A rule of ESLint core has no prefix either: `core` tells it from a typescript-eslint one.
  rules.push({ rule: namespace === '@typescript-eslint' ? name : id, ...(namespace === '' ? { core: true } : {}), cases: casesOf(namespace, standIns[namespace], id, schema, first, limit) });
}

// Schemas for what the rules do not exercise. Each is the meta.schema of a rule of its own.
const syntheticSchemas = {
  // A type and an enum inside a composite rule: both are reported there.
  'composite-type-enum': [{ oneOf: [{ type: 'string', enum: ['a', 'b'] }, { type: 'number' }, { type: 'null' }] }],
  'any-of': [{ anyOf: [{ type: 'string', minLength: 2 }, { type: 'array', items: { type: 'boolean' }, minItems: 1, maxItems: 2 }] }],
  'any-of-open': [{ anyOf: [{ type: 'string' }, {}] }, { anyOf: [{ type: 'string' }, { type: 'object', anyOf: [{ required: ['a'] }, { required: ['b'] }] }] }],
  not: [{ not: { type: 'string' } }, { not: {} }, { not: { not: { type: 'object', required: ['a'] } } }],
  'all-of': [{ allOf: [{ type: 'object', required: ['a', 'b'] }, { properties: { a: { type: 'string' } } }, {}] }],
  // A required property without a schema of its own is named as code would read it.
  required: [{ type: 'object', properties: { a: {}, b: { type: 'string' }, 'c d': {} }, required: ['a', 'b', 'c d', "e'f", 'g\\h'] }],
  'required-only': [{ required: ['a', 'b c', '0'] }, { type: 'object', required: ['x'], additionalProperties: false }],
  'additional-schema': [{ type: 'object', properties: { a: { type: 'string' } }, additionalProperties: { type: 'number' } },
    { type: 'object', additionalProperties: false }, { additionalProperties: { enum: [1, 'a'] } }, { type: 'object', additionalProperties: {} }],
  'many-properties': [{ type: 'object', additionalProperties: false,
    properties: Object.fromEntries(['b', 'a', 'c', 'd', 'e', 'f', 'g', 'h', 'i', '10', '2'].map(name => [name, { type: 'boolean' }])) }],
  tuple: [{ type: 'array', items: [{ type: 'string' }, { type: 'number' }], additionalItems: false },
    { type: 'array', items: [{ type: 'string' }, {}, { type: 'null' }], additionalItems: { type: 'boolean' } },
    { items: [{ enum: [1] }] }],
  unique: [{ type: 'array', items: { type: 'number' }, uniqueItems: true }, { type: 'array', items: { type: ['string', 'number', 'null'] }, uniqueItems: true },
    { type: 'array', uniqueItems: true }, { type: 'array', items: { type: 'object' }, uniqueItems: true },
    { type: 'array', items: { type: ['string'] }, uniqueItems: true }, { uniqueItems: true, minItems: 2, maxItems: 4 }, { type: 'array', items: { type: 'boolean' }, uniqueItems: false }],
  numbers: [{ type: 'integer' }, { type: 'number' }, { type: ['integer', 'null'] }, { type: ['number', 'string'] }],
  // A list of types is checked first, and the rules of a later group are then skipped.
  'type-list': [{ type: ['string', 'null'], minLength: 2, enum: ['ab', null, 'abc', 'a'] }, { type: ['array', 'object'], minItems: 1, minProperties: 1 },
    { type: ['boolean'] }, { type: ['string'], maxLength: 1 }],
  constant: [{ const: { a: [1, 2] } }, { const: null }, { const: 'x', type: 'string' }],
  enumeration: [{ enum: [[1], { a: 1, b: [null] }, null, 1, 'a', true] }, { type: 'boolean', enum: [true] }],
  lengths: [{ type: 'string', minLength: 2, maxLength: 3 }, { maxLength: 0 }, { type: 'string', maxLength: 2, enum: ['a', 'abc'] }],
  'property-counts': [{ type: 'object', minProperties: 1, maxProperties: 2 }, { maxProperties: 0 }],
  booleans: [{ type: 'object', properties: { a: false, b: true } }, { type: 'array', items: false }, { oneOf: [false, { type: 'string' }] }, { anyOf: [true, { type: 'string' }] }],
  'nested-one-of': [{ oneOf: [{ type: 'object', properties: { a: { oneOf: [{ type: 'string' }, { type: 'number' }] } }, required: ['a'], additionalProperties: false },
    { type: 'array', items: { oneOf: [{ type: 'string', enum: ['x'] }, { type: 'boolean' }] } }] }],
  'two-match': [{ oneOf: [{ type: 'string' }, { minLength: 1 }, { type: 'object' }, { required: ['a'] }, { enum: ['never looked at'] }] }],
  'object-only': [{ type: 'object' }, { type: 'array' }, { type: 'string' }, { type: 'null' }],
  'index-names': [{ type: 'object', properties: { b: { type: 'string' }, 10: { type: 'string' }, 2: { type: 'string' } }, additionalProperties: false, required: ['2', 'b'] }],
  // A schema that is not a list.
  'whole-schema': { type: 'array', items: { type: 'string', minLength: 1 }, minItems: 1, uniqueItems: true },
  // A reference to a schema without references is compiled in place (and keeps the composite rule
  // it is in); to one with references, as a function of its own, which stops at its first error.
  references: { type: 'array', maxItems: 2,
    items: [
      { oneOf: [{ $ref: '#/definitions/letter' }, { type: 'null' }, { $ref: '#/definitions/wrapped' }] },
      { type: 'object', additionalProperties: false, properties: {
        direct: { $ref: '#/definitions/letter' },
        described: { $ref: '#/definitions/letter', description: 'only this next to it' },
        typed: { $ref: '#/definitions/letter', type: 'number' },
        missing: { $ref: '#/definitions/nope' },
        chained: { $ref: '#/definitions/alias' },
        list: { $ref: '#/definitions/list' },
        choice: { $ref: '#/definitions/choice' },
        escaped: { $ref: '#/definitions/a~1b' },
      } },
    ],
    definitions: {
      letter: { type: 'string', enum: ['x', 'y'] },
      alias: { $ref: '#/definitions/letter' },
      wrapped: { type: 'string', enum: ['z'], properties: { unused: { $ref: '#/definitions/letter' } } },
      list: { type: 'array', items: { $ref: '#/definitions/letter' }, minItems: 1 },
      choice: { oneOf: [{ $ref: '#/definitions/list' }, { type: 'boolean' }] },
      'a/b': { type: 'boolean' },
    } },
  recursive: { type: 'array', maxItems: 1,
    items: [{ type: 'object', additionalProperties: false, properties: { name: { type: 'string' }, child: { $ref: '#/items/0' }, whole: { $ref: '#' } } }] },
};
const syntheticExtra = {
  references: [['x'], ['w'], [5], [null], ['z'], [true], [{}], [null, { direct: 5 }], [null, { described: 5 }], [null, { typed: 5 }], [null, { typed: 'x' }],
    [null, { typed: 'w' }], [null, { missing: 5 }], [null, { chained: 5 }], [null, { chained: 'y' }], [null, { list: [] }], [null, { list: ['x', 5] }],
    [null, { choice: 5 }], [null, { choice: [5] }], [null, { choice: true }], [null, { choice: ['y'] }], [null, { escaped: 5 }], [null, { escaped: true }], [null, { nope: 1 }]],
  recursive: [[{ name: 'a', child: { name: 'b', child: { name: 5 } } }], [{ child: { nope: 1 } }], [{ whole: [{ name: 5 }] }], [{ whole: [{}, {}] }], [{ whole: 5 }], [{ child: 5 }], [{ name: 'a', child: { child: {} } }]],
  required: [[{}], [{ a: 1 }], [{ a: 1, b: 'x' }], [{ a: 1, b: 'x', 'c d': 1 }], [{ a: 1, b: 'x', 'c d': 1, "e'f": 1 }], [{ a: 1, b: 'x', 'c d': 1, "e'f": 1, 'g\\h': 1 }], [{ b: 5 }], [{ a: 1, 'c d': 1, "e'f": 1, 'g\\h': 1 }]],
  'two-match': [['x'], [''], [{}], [{ a: 1 }], [5], [[]], ['never looked at']],
  'type-list': [['a'], [5], [null], ['abcd'], ['ab'], [''], [null, []], [null, {}], [null, 5], [null, [1]], [null, { a: 1 }], [null, [1], 5], [null, [1], true, 'ab'], [null, [1], true, 5]],
};
const synthetic = [];
for (const [name, metaSchema] of Object.entries(syntheticSchemas)) {
  const rule = { meta: { schema: metaSchema }, create: () => ({}) };
  const schema = Config.getRuleOptionsSchema(rule);
  checkSchema(schema, `synthetic/${name}`);
  synthetic.push({ name, schema, cases: casesOf('synthetic', { [name]: rule }, `synthetic/${name}`, schema, syntheticExtra[name] ?? [], 400) });
}

// The value of a rule in a configuration, when it is not a severity or a list that starts with one:
// what the eslint command prints for the error (getErrorMessage of bin/eslint.js: the text of
// messages/<messageTemplate>.js, or the message of the error).
function valueMessage(id, value) {
  try {
    linter.verify('', [{ plugins: { '@typescript-eslint': { rules: standIns['@typescript-eslint'] } }, rules: { [id]: value } }], { filename: 'a.js' });
    return null;
  } catch (error) {
    if (typeof error.messageTemplate === 'string') {
      return require(path.join(modules, `eslint/messages/${error.messageTemplate}.js`))(error.messageData || {});
    }
    return error.message;
  }
}
const ruleValues = ['error', 'warn', 'off', 2, 1, 0, 2.0, -0, ['error'], [1], ['off', { nope: 1 }], [0, 5], 'sometimes', 'ERROR', 'Off', '', 3, -1, 0.5, 1.5,
  null, true, false, {}, { a: 1 }, { ignoreVoid: [true, { deep: null }], also: 'x' }, [], [null], [true], ['sometimes'], [3, { ignoreVoid: true }], [[2]],
  [{ ignoreVoid: true }], ['2'], ['error', { nope: 1 }], [2, { ignoreVoid: 'yes' }], ['warn', 1, 2]];
const values = ruleValues.map(value => ({ value, message: valueMessage('@typescript-eslint/no-floating-promises', value) }));

const file = path.join(root, 'tests/rule_option_cases.json');
const versions = { node: process.version, eslint: version('eslint'), 'typescript-eslint': version('@typescript-eslint/eslint-plugin'), ajv: version('ajv') };
// One case per line: the file is large, and a change in it should read as the cases that changed.
const group = (key, entry) => `{${JSON.stringify(key)}:${JSON.stringify(entry[key])},${entry.core ? '"core":true,' : ''}${entry.schema ? `"schema":${JSON.stringify(entry.schema)},` : ''}"cases":[\n${entry.cases.map(({ rejected, ...c }) => JSON.stringify(c)).join(',\n')}\n]}`;
fs.writeFileSync(file, `{"versions":${JSON.stringify(versions)},\n"schemas":${JSON.stringify(schemas)},\n"ruleDefaults":${JSON.stringify(Object.fromEntries(ruleDefaults(builtinRules, { '@typescript-eslint': plugin, seyfert: seyfertPlugin(root) })))},\n"rules":[\n${rules.map(entry => group('rule', entry)).join(',\n')}\n],\n"synthetic":[\n${synthetic.map(entry => group('name', entry)).join(',\n')}\n],\n"values":[\n${values.map(entry => JSON.stringify(entry)).join(',\n')}\n]}\n`);
const count = groups => groups.reduce((sum, entry) => sum + entry.cases.length, 0);
const invalid = groups => groups.reduce((sum, entry) => sum + entry.cases.filter(c => c.rejected).length, 0);
console.log(`${count(rules)} cases of ${rules.length} rules (${invalid(rules)} that ESLint rejects), ${count(synthetic)} of ${synthetic.length} other schemas (${invalid(synthetic)}), ${values.length} values of a rule; ${(fs.statSync(file).size / 1024).toFixed(0)} KiB`);
