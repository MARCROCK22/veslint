// The builtin objects a constant expression can reach in getStaticValue of
// @eslint-community/eslint-utils, as the Node that runs this script has them (the engine ESLint
// runs on): the globals of its builtinNames and everything their data properties and prototypes
// lead to, each with a canonical name (`String.prototype.slice`), for
// tools/gen_static_value_cases.mjs (the expected values of rules/static_value_test.v), which
// writes a builtin object as its name.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

export const root = path.resolve(import.meta.dirname, '..');
const require = createRequire(import.meta.url);
const pluginPath = require.resolve('@typescript-eslint/eslint-plugin/package.json', {
  paths: [path.join(root, 'build/eval/spider-byte')],
});
// The eslint-utils typescript-eslint's rules load.
export const eslintUtilsPath = require.resolve('@eslint-community/eslint-utils', { paths: [path.dirname(pluginPath)] });
export const eslintUtilsVersion = JSON.parse(
  fs.readFileSync(path.join(path.dirname(eslintUtilsPath), 'package.json'), 'utf8'),
).version;

// builtinNames, callAllowed, callPassThrough and getterAllowed are private to eslint-utils: its
// own source text builds them here, in this realm.
function privateSets() {
  const source = fs.readFileSync(eslintUtilsPath, 'utf8');
  const start = source.indexOf('const globalObject =');
  const end = source.indexOf('function getPropertyDescriptor(');
  if (start < 0 || end < start) throw new Error('eslint-utils: the builtin sets were not found');
  const slice = source.slice(start, source.lastIndexOf('/**', end));
  for (const name of ['builtinNames', 'callAllowed', 'callPassThrough', 'getterAllowed']) {
    if (!slice.includes(`const ${name} =`)) throw new Error(`eslint-utils: ${name} was not found`);
  }
  return new Function(`${slice}; return { builtinNames, callAllowed, callPassThrough, getterAllowed };`)();
}
export const { builtinNames, callAllowed, callPassThrough, getterAllowed } = privateSets();

const isObject = value => (typeof value === 'object' && value !== null) || typeof value === 'function';

// symbolName is the name of a well-known symbol (`Symbol.iterator`), its description.
const wellKnown = new Map(
  Reflect.ownKeys(Symbol)
    .filter(key => typeof Symbol[key] === 'symbol')
    .map(key => [Symbol[key], `Symbol.${key}`]),
);
export function symbolName(symbol) {
  const name = wellKnown.get(symbol);
  if (name === undefined || name !== symbol.description) throw new Error(`unknown symbol ${String(symbol)}`);
  return name;
}
export const wellKnownSymbols = [...wellKnown.values()];

// Objects no data property leads to: the prototypes of the iterators the allowed functions
// return, and the ones named here when a prototype chain reaches them.
const hiddenRoots = [
  ['%ArrayIteratorPrototype%', Object.getPrototypeOf([][Symbol.iterator]())],
  ['%MapIteratorPrototype%', Object.getPrototypeOf(new Map()[Symbol.iterator]())],
  ['%SetIteratorPrototype%', Object.getPrototypeOf(new Set()[Symbol.iterator]())],
];
const hiddenNames = new Map([
  [Object.getPrototypeOf(Int8Array), 'TypedArray'],
  [Object.getPrototypeOf(Int8Array.prototype), 'TypedArray.prototype'],
  [Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]())), '%IteratorPrototype%'],
]);

// walk gives the reachable objects in a stable order, each with its canonical name: the shortest
// path of data properties from a global, and of two as short the one that ends with the
// function's own name (`trimStart`, not `trimLeft`).
function walk() {
  const names = new Map();
  const order = [];
  let level = [];
  const offer = (object, name, key) => {
    if (!isObject(object) || names.has(object)) return;
    const found = level.find(entry => entry.object === object);
    if (!found) {
      level.push({ object, name, key });
    } else if (found.key !== object.name && key === object.name) {
      found.name = name;
      found.key = key;
    }
  };
  const flush = () => {
    const added = level;
    level = [];
    for (const { object, name } of added) {
      names.set(object, name);
      order.push(object);
    }
    return added.map(entry => entry.object);
  };
  for (const name of builtinNames) {
    if (name in globalThis) offer(globalThis[name], name, name);
  }
  let frontier = flush();
  const expand = () => {
    while (frontier.length > 0) {
      for (const object of frontier) {
        const base = names.get(object);
        for (const key of Reflect.ownKeys(object)) {
          const descriptor = Object.getOwnPropertyDescriptor(object, key);
          if (!('value' in descriptor)) continue;
          const name = typeof key === 'symbol' ? `${base}[${symbolName(key)}]` : `${base}.${key}`;
          offer(descriptor.value, name, typeof key === 'symbol' ? `[${symbolName(key)}]` : key);
        }
      }
      frontier = flush();
    }
  };
  expand();
  for (const [name, object] of hiddenRoots) offer(object, name, name);
  frontier = flush();
  expand();
  // Prototypes that only a chain reaches.
  for (;;) {
    for (const object of order) {
      const proto = Object.getPrototypeOf(object);
      if (proto !== null) offer(proto, hiddenNames.get(proto) ?? `%${names.get(object)}.__proto__%`, '');
    }
    frontier = flush();
    if (frontier.length === 0) break;
    expand();
  }
  return { names, order };
}

const { names, order } = walk();
// builtinObjects are the reachable objects, and builtinName(object) the canonical name of one
// (undefined for any other object).
export const builtinObjects = order;
export const builtinName = object => names.get(object);
// The names of the functions eslint-utils calls, and of the ones it only passes through.
export const callAllowedNames = [...callAllowed].map(f => {
  const name = names.get(f);
  if (name === undefined) throw new Error(`callAllowed has a function that is not reachable: ${f.name}`);
  return name;
});
export const callPassThroughNames = [...callPassThrough].map(f => names.get(f));
export const getterAllowedNames = getterAllowed.map(([constructor, allowed]) => [names.get(constructor), [...allowed]]);
