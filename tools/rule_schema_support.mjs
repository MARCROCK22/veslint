// Shared by tools/gen_rule_schemas.mjs and tools/gen_rule_option_cases.mjs: the ported rules, the
// default options of ESLint's rules, and which JSON schema keywords rules/json_schema.v validates.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

// portedRules are the ids of the rules of rules/rules.v, in the order of its `names`
// (`@typescript-eslint/await-thenable`, `seyfert/require-declare`).
export function portedRules(root) {
  const source = fs.readFileSync(path.join(root, 'rules/rules.v'), 'utf8');
  // A rule id with a plugin, or without one (ESLint core).
  const byConst = new Map([...source.matchAll(/^pub const (\w+) = '((?:(?:@typescript-eslint|seyfert|unicorn)\/)?[a-z0-9-]+)'$/gm)].map(m => [m[1], m[2]]));
  const list = /^pub const names = \[([^\]]+)\]/m.exec(source);
  if (!list) {
    throw new Error('rules/rules.v: `names` not found');
  }
  return list[1].split(',').map(item => {
    const name = byConst.get(item.trim());
    if (!name) {
      throw new Error(`rules/rules.v: no constant ${item.trim()}`);
    }
    return name;
  });
}

// ruleDefaults are the meta.defaultOptions of the rules of ESLint (`builtinRules`) and of the
// plugins (`plugins`, by namespace) that have any, as [rule id, options], sorted by id.
export function ruleDefaults(builtinRules, plugins) {
  // ESLint core (plugins['']) is builtinRules itself.
  const all = [...builtinRules].concat(
    Object.entries(plugins)
      .filter(([namespace]) => namespace)
      .flatMap(([namespace, plugin]) => Object.entries(plugin.rules).map(([name, rule]) => [`${namespace}/${name}`, rule])),
  );
  return all
    .filter(([, rule]) => Array.isArray(rule.meta?.defaultOptions) && rule.meta.defaultOptions.length > 0)
    .map(([id, rule]) => [id, rule.meta.defaultOptions])
    .sort(([a], [b]) => (a < b ? -1 : 1));
}

// The keywords rules/json_schema.v validates (schema_rule_groups there), the ones that hold
// subschemas, and the ones ajv ignores when it validates.
const jsonTypes = ['array', 'boolean', 'integer', 'null', 'number', 'object', 'string'];
const supported = new Set(['type', 'enum', 'const', 'maximum', 'minimum', 'properties', 'additionalProperties', 'required', 'items',
  'additionalItems', 'minItems', 'maxItems', 'uniqueItems', 'minLength', 'maxLength', 'pattern', 'minProperties',
  'maxProperties', 'oneOf', 'anyOf', 'allOf', 'not', '$ref']);
const annotations = new Set(['description', 'title', '$defs', 'definitions']);

// checkSchema throws for a schema rules/json_schema.v would not validate like ajv: an unknown
// keyword, a `$ref` that is not a pointer into the same schema, or an unknown type. `default` (ESLint's
// ajv fills the options in with it) is taken only where it is the value meta.defaultOptions (the
// rule's `defaultOptions`) has at that place, which veslint applies anyway: the property of an
// object of the list of options, at `valuePath` (null where no single place is known).
export function checkSchema(schema, where, defaultOptions = undefined, valuePath = []) {
  if (typeof schema === 'boolean') {
    return;
  }
  if (typeof schema !== 'object' || schema === null || Array.isArray(schema)) {
    throw new Error(`${where}: a schema must be an object or a boolean`);
  }
  for (const [key, value] of Object.entries(schema)) {
    const at = `${where}/${key}`;
    if (key === 'default') {
      const known = valuePath && defaultOptions !== undefined
        ? valuePath.reduce((holder, step) => (holder === undefined || holder === null ? undefined : holder[step]), defaultOptions)
        : undefined;
      if (JSON.stringify(known) !== JSON.stringify(value)) {
        throw new Error(`${at}: rules/json_schema.v does not implement the keyword \`default\` (it is not the value of meta.defaultOptions there)`);
      }
      continue;
    }
    if (!supported.has(key) && !annotations.has(key)) {
      throw new Error(`${at}: rules/json_schema.v does not implement the keyword \`${key}\``);
    }
    switch (key) {
      case 'type':
        for (const type of [value].flat()) {
          if (!jsonTypes.includes(type)) {
            throw new Error(`${at}: unknown type ${JSON.stringify(type)}`);
          }
        }
        break;
      case '$ref':
        if (typeof value !== 'string' || !/^#(\/|$)/.test(value)) {
          throw new Error(`${at}: only a pointer into the same schema is supported, got ${JSON.stringify(value)}`);
        }
        break;
      case 'properties':
        for (const [name, sub] of Object.entries(value)) {
          checkSchema(sub, `${at}/${name}`, defaultOptions, valuePath && [...valuePath, name]);
        }
        break;
      case '$defs':
      case 'definitions':
        for (const [name, sub] of Object.entries(value)) {
          checkSchema(sub, `${at}/${name}`, defaultOptions, null);
        }
        break;
      case 'oneOf':
      case 'anyOf':
      case 'allOf':
        value.forEach((sub, i) => checkSchema(sub, `${at}/${i}`, defaultOptions, null));
        break;
      case 'items':
        // A list of schemas gives the place of each item; a single schema, of none.
        [value].flat().forEach((sub, i) => checkSchema(sub, `${at}/${i}`, defaultOptions,
          Array.isArray(value) && valuePath ? [...valuePath, i] : null));
        break;
      case 'additionalProperties':
      case 'additionalItems':
      case 'not':
        checkSchema(value, at, defaultOptions, null);
        break;
      default:
    }
  }
}

// seyfertPlugin is @slipher/eslint-plugin 1.1.0, the plugin of the `seyfert/*` rules, from
// build/upstream/seyfert (tests/upstream/README.md).
export function seyfertPlugin(root) {
  const require = createRequire(path.join(root, 'build/upstream/seyfert/package.json'));
  return require('@slipher/eslint-plugin').plugin;
}

// unicornPlugin is eslint-plugin-unicorn 64.0.0, the plugin of the `unicorn/*` rules, from
// build/eval.
export function unicornPlugin(root) {
  const require = createRequire(path.join(root, 'build/eval/spider-byte/package.json'));
  const module = require('eslint-plugin-unicorn');
  return module.default ?? module;
}

// pluginOf is the namespace, the plugin and the name in it of a ported rule.
export function pluginOf(id, plugins) {
  // ESLint core: a rule id without a plugin; plugins[''] holds its rules.
  if (!id.includes('/')) return ['', plugins[''], id];
  const namespace = id.startsWith('seyfert/') ? 'seyfert' : id.startsWith('unicorn/') ? 'unicorn' : '@typescript-eslint';
  return [namespace, plugins[namespace], id.slice(namespace.length + 1)];
}
