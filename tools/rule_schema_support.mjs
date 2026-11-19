// Shared by tools/gen_rule_schemas.mjs and tools/gen_rule_option_cases.mjs: the ported rules, the
// default options of ESLint's rules, and which JSON schema keywords rules/json_schema.v validates.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

// portedRules are the ids of the rules of rules/rules.v, in the order of its `names`
// (`@typescript-eslint/await-thenable`, `seyfert/require-declare`,
// `svelte/@typescript-eslint/no-unnecessary-condition`).
export function portedRules(root) {
  const source = fs.readFileSync(path.join(root, 'rules/rules.v'), 'utf8');
  // A rule id with a plugin, or without one (ESLint core).
  const byConst = new Map([...source.matchAll(/^pub const (\w+) = '((?:(?:@typescript-eslint|@stylistic|@eslint-community\/eslint-comments|perfectionist|marcrock|promise|seyfert|unicorn|vue|svelte)\/)?(?:@typescript-eslint\/)?[a-z0-9-]+)'$/gm)].map(m => [m[1], m[2]]));
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

// jsonInfinity is the replacer of JSON.stringify for what goes to veslint: Infinity (which JSON
// writes as null) is the largest finite number, which ajv also takes as an integer and which compares
// like Infinity with the numbers of the options.
export const jsonInfinity = (key, value) => (value === Infinity ? Number.MAX_VALUE : value === -Infinity ? -Number.MAX_VALUE : value);

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
  'maxProperties', 'oneOf', 'anyOf', 'allOf', 'not', '$ref', 'patternProperties', 'exclusiveMinimum', 'exclusiveMaximum']);
const annotations = new Set(['description', 'title', '$defs', 'definitions']);

// checkSchema throws for a schema rules/json_schema.v would not validate like ajv: an unknown
// keyword, a `$ref` that is not a pointer into the same schema, or an unknown type. `default` (ESLint's
// ajv fills the options in with it) is taken only where it is the value meta.defaultOptions (the
// rule's `defaultOptions`) has at that place, which veslint applies anyway: the property of an
// object of the list of options, at `valuePath` (null where no single place is known).
// `defaultsIgnored`: inside anyOf, oneOf or not, where ajv's useDefaults does not apply a `default`.
export function checkSchema(schema, where, defaultOptions = undefined, valuePath = [], defaultsIgnored = false) {
  if (typeof schema === 'boolean') {
    return;
  }
  if (typeof schema !== 'object' || schema === null || Array.isArray(schema)) {
    throw new Error(`${where}: a schema must be an object or a boolean`);
  }
  for (const [key, value] of Object.entries(schema)) {
    const at = `${where}/${key}`;
    if (key === 'default') {
      if (defaultsIgnored) continue;
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
          checkSchema(sub, `${at}/${name}`, defaultOptions, valuePath && [...valuePath, name], defaultsIgnored);
        }
        break;
      case 'patternProperties':
        for (const [pattern, sub] of Object.entries(value)) {
          checkSchema(sub, `${at}/${pattern}`, defaultOptions, null, defaultsIgnored);
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
        value.forEach((sub, i) => checkSchema(sub, `${at}/${i}`, defaultOptions, null, true));
        break;
      case 'allOf':
        value.forEach((sub, i) => checkSchema(sub, `${at}/${i}`, defaultOptions, null, defaultsIgnored));
        break;
      case 'items':
        // A list of schemas gives the place of each item; a single schema, of none.
        [value].flat().forEach((sub, i) => checkSchema(sub, `${at}/${i}`, defaultOptions,
          Array.isArray(value) && valuePath ? [...valuePath, i] : null, defaultsIgnored));
        break;
      case 'additionalProperties':
      case 'additionalItems':
        checkSchema(value, at, defaultOptions, null, defaultsIgnored);
        break;
      case 'not':
        checkSchema(value, at, defaultOptions, null, true);
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

// unicornPlugin is eslint-plugin-unicorn 79.0.0, the plugin of the `unicorn/*` rules, from
// build/eval.
export function unicornPlugin(root) {
  const require = createRequire(path.join(root, 'build/eval/spider-byte/package.json'));
  const module = require('eslint-plugin-unicorn');
  return module.default ?? module;
}

// stylisticPlugin is @stylistic/eslint-plugin 5.10.0, the plugin of the `@stylistic/*` rules, from
// build/eval.
export function stylisticPlugin(root) {
  const require = createRequire(path.join(root, 'build/eval/spider-byte/package.json'));
  const module = require('@stylistic/eslint-plugin');
  return module.default ?? module;
}

// perfectionistPlugin is eslint-plugin-perfectionist 5.13.0, the plugin of the `perfectionist/*`
// rules, from build/upstream/perfectionist-deps (an ES module: imported).
export async function perfectionistPlugin(root) {
  return (await import(path.join(root, 'build/upstream/perfectionist-deps/node_modules/eslint-plugin-perfectionist/dist/index.js'))).default;
}

// marcrockPlugin is the plugin of the `marcrock/*` rules, @marcrock22/eslintcf's own, from build/eval
// (an ES module: imported).
export async function marcrockPlugin(root) {
  return (await import(path.join(root, 'build/eval/spider-byte/node_modules/@marcrock22/eslint/dist/rules/_.js'))).default;
}

// promisePlugin is eslint-plugin-promise 7.3.0, the plugin of the `promise/*` rules, from
// build/upstream/plugins-new (tests/upstream/README.md).
export function promisePlugin(root) {
  const require = createRequire(path.join(root, 'build/upstream/plugins-new/package.json'));
  return require('eslint-plugin-promise');
}

// vuePlugin is eslint-plugin-vue 10.12.1, the plugin of the `vue/*` rules, from
// build/upstream/vue-deps (tests/upstream/README.md).
export function vuePlugin(root) {
  const require = createRequire(path.join(root, 'build/upstream/vue-deps/package.json'));
  return require('eslint-plugin-vue');
}

// sveltePlugin is eslint-plugin-svelte 3.24.1, the plugin of the `svelte/*` rules, from
// build/upstream/svelte-deps (tests/upstream/README.md).
export function sveltePlugin(root) {
  const require = createRequire(path.join(root, 'build/upstream/svelte-deps/package.json'));
  return require('eslint-plugin-svelte');
}

// eslintCommentsPlugin is @eslint-community/eslint-plugin-eslint-comments 4.8.1, the plugin of the
// `@eslint-community/eslint-comments/*` rules, from build/upstream/plugins-new
// (tests/upstream/README.md).
export function eslintCommentsPlugin(root) {
  const require = createRequire(path.join(root, 'build/upstream/plugins-new/package.json'));
  return require('@eslint-community/eslint-plugin-eslint-comments');
}

// pluginOf is the namespace, the plugin and the name in it of a ported rule.
export function pluginOf(id, plugins) {
  // ESLint core: a rule id without a plugin; plugins[''] holds its rules.
  if (!id.includes('/')) return ['', plugins[''], id];
  const namespace = id.startsWith('seyfert/')
    ? 'seyfert'
    : id.startsWith('unicorn/')
      ? 'unicorn'
      : id.startsWith('@stylistic/')
        ? '@stylistic'
        : id.startsWith('perfectionist/')
          ? 'perfectionist'
          : id.startsWith('marcrock/')
            ? 'marcrock'
            : id.startsWith('promise/')
              ? 'promise'
            : id.startsWith('vue/')
              ? 'vue'
              : id.startsWith('svelte/')
                ? 'svelte'
                : id.startsWith('@eslint-community/eslint-comments/')
                  ? '@eslint-community/eslint-comments'
                  : '@typescript-eslint';
  return [namespace, plugins[namespace], id.slice(namespace.length + 1)];
}
