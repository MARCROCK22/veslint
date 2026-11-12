// Generates tests/static_value_cases.json for rules/static_value_test.v: what getStaticValue of
// @eslint-community/eslint-utils (the one typescript-eslint's rules call) gives for each
// expression statement of a TypeScript source, asked from a rule that ESLint runs with
// typescript-eslint's parser, like the ported rules do (`getStaticValue(node, globalScope)`).
// The expected values are eslint-utils' own answers, not a reading of its code.
//
// ESLint runs three times, in fresh processes with different time zones and locales: a value
// that is not the same in the three depends on the environment (or on the clock) and is written
// as `ENV`, which veslint must answer "not static" to.
//
// Node runs this script at development time only. Usage: node tools/gen_static_value_cases.mjs
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import {
  builtinName,
  builtinObjects,
  callAllowedNames,
  callPassThroughNames,
  eslintUtilsPath,
  eslintUtilsVersion,
  root,
  symbolName,
} from './js_builtins.mjs';

// The packages of the reference ESLint (tests/eval_spider_byte.sh installs them).
const reference = createRequire(path.join(root, 'build/eval/spider-byte/package.json'));

// ---------------------------------------------------------------------------------------------
// The source: declarations, then one `(expression);` statement per line.

// The limits of rules/static_value.v: what eslint-utils evaluates and veslint answers "not static"
// to. A statement written under one of them may have no value in veslint; under none, veslint's
// value must be eslint-utils'. rules/static_value_test.v checks both, and that each limit still
// holds.
const limits = {
  date: 'Date: `Date()`, `new Date(…)` and `Date.parse`',
  'symbol-key': 'a property read or defined with a symbol key',
  'builtin-property': 'the properties of the builtin functions other than their `length`, `name` and static members, and the prototype objects (`String.prototype`, and `__proto__` read from a primitive)',
  'native-call': 'a builtin function outside callAllowed that a builtin calls, whose result veslint does not model (`JSON.stringify`, `Array.from`…): a callback of `every`, `filter`, `find`, `findIndex` or `some`, the `join` that `Array.prototype.toString` calls, the `toString` or `valueOf` of an object converted to a primitive (where the methods that convert their receiver are not called either)',
  'bigint-size': 'a BigInt of more than 2^16 bits made by `**` or `<<` (V8 goes up to 2^30)',
  'long-value': 'a string of more than 2^20 units made by `padStart`, `padEnd` or `String.raw`, or an array-like object of more than 2^20 elements as the receiver of an array method',
  depth: 'an expression or a chain of constants more than 100 levels deep',
};

const chainLength = 130;
const declarations = String.raw`const one = 1;
const text = 'key';
const list = [1, 2];
const record = { k: 'v', n: 2 };
const regexp = /re/g;
const sum = one + 1;
const chain = sum;
let neverWritten = 'n';
let reassigned = 1;
reassigned = 2;
let updated = 1;
updated++;
let nonNullUpdated = 1;
nonNullUpdated!++;
let castAssigned = 1;
(castAssigned as number) = 2;
var dup = 1;
var dup = 2;
let uninitialized;
const { destructured } = { destructured: 1 };
const pushed = [1];
pushed.push(2);
const sorted = [1];
sorted['sort']();
const member = { a: [1] };
member.a.length = 0;
const optional = [1];
optional?.push(2);
const chained = { a: 1 };
(chained?.a, 0);
const self = self;
const cycleA = cycleB;
const cycleB = cycleA;
function declared() {}
class Klass {}
declare const ambient: string;
const shadow = 'outer';
function inner(param: number) {
  const shadow = 'inner';
  return [param, shadow];
}
const map = new Map<unknown, unknown>([[1, 'one'], ['k', [2]], [NaN, 0]]);
const set = new Set<unknown>([1, 'a', 1, -0]);
const written = new Map<unknown, unknown>();
written.set('a', 1);
const added = new Set<unknown>();
added.add(1);
const cleared = new Map([[1, 2]]);
cleared.clear();
const assigned = new Map<unknown, unknown>();
(assigned as any).extra = 1;
const nullKey = [1];
nullKey[ambient]();
const __proto__ = 1;
const deep0 = 1;
${Array.from({ length: chainLength }, (_, i) => `const deep${i + 1} = deep${i};`).join('\n')}
`;

// Declarations that the sections below add; an expression statement among them may be written
// under a limit too.
let moreDeclarations = '';
const declaredTags = new Map();
const declare = (text, limitName = '') => {
  const first = (declarations + moreDeclarations).split('\n').length;
  if (limitName !== '') {
    if (!(limitName in limits)) throw new Error(`unknown limit ${limitName}`);
    for (const i of text.split('\n').keys()) declaredTags.set(first + i, limitName);
  }
  moreDeclarations += `${text}\n`;
};

const cases = [];
let tag = '';
const add = (...codes) => {
  for (const code of codes.flat()) cases.push({ code, tag });
};
// expect adds a statement that must be static, or not, in eslint-utils: a check of what this
// file says about it.
const expect = (code, isStatic) => {
  cases.push({ code, tag, isStatic });
};
const limit = (name, fill) => {
  if (!(name in limits)) throw new Error(`unknown limit ${name}`);
  tag = name;
  fill();
  tag = '';
};
const split = text => text.split('\n');

// The statements of the first version of the test (computed by hand from ESLint then).
add(split(String.raw`1
-0
0x10
1_000
1e21
0.1 + 0.2
12345678901234567890n
'aA\n'
"😀".length
${'`t${one}${list}${record}${regexp}`'}
true
null
/a\/b/giu
/(/
/a/gg
one
text
list
record
regexp
sum
chain
neverWritten
reassigned
updated
nonNullUpdated
castAssigned
dup
uninitialized
destructured
pushed
sorted
member
optional
chained
self
cycleA
declared
Klass
ambient
shadow
undefined
NaN
Infinity
Math.PI
Number.MAX_SAFE_INTEGER
String.length
String.name
Date.length
Int8Array.BYTES_PER_ELEMENT
RegExp.lastMatch
globalThis
unknownName
typeof one
void one
!one
~one
-'3'
+'0x10'
+1n
-1n
1n + 1
2n ** 64n
7 % -2
(-7) % 2
2 ** 0.5
(-8) >>> 1
'b' > 'a'
null == undefined
null === undefined
[] + {}
[1, [2, 3]] + ''
one && text
0 || 'fallback'
null ?? 'default'
one ? 'yes' : 'no'
(one, text)
text as string
text satisfies string
<string>text
list!
list[0]
list['1']
list[2]
list.length
text[0]
text.length
record.k
record['n']
record.missing
record.toString
regexp.source
regexp.flags
regexp.global
regexp.lastIndex
regexp.unicodeSets
record?.k
null?.a.b
undefined?.()
[1, , 3]
[...list, ...'ab']
{ ...record, [text]: 1, 2: 'two', 1: 'one' }
{ m() {} }
{ get g() { return 1; } }
String(one)
String(Symbol.iterator)
Number('12px')
Number(5n)
parseInt('12px')
parseInt('0x1F')
parseInt('z', 36)
parseFloat('1.5e3x')
isNaN('x')
Boolean('')
RegExp('a', 'g')
new RegExp('a/b')
new RegExp(regexp)
RegExp(regexp)
new RegExp('(')
Array.isArray(list)
Array.of(1, 2)
Math.max(1, 3, 2)
Math.min()
Math.round(-0.5)
Math.round(2.5)
Math.sign(-3)
Math.trunc(-1.7)
Math.sqrt(4)
Object.freeze(list)
'abc'.at(-1)
'abc'.charAt(1)
'abc'.charCodeAt(0)
'😀'.codePointAt(0)
'a'.concat('b', 1)
'abc'.endsWith('c')
'abc'.includes('b', 2)
'abcb'.indexOf('b', 2)
'abcb'.lastIndexOf('b')
'7'.padStart(3, '0')
'7'.padEnd(3)
'abcdef'.slice(-3, -1)
'abcdef'.substring(4, 1)
'abcdef'.substr(-4, 2)
'abc'.startsWith('ab')
'  a  '.trim()
'  a  '.trimStart()
'  a  '.trimEnd()
[1, 2, 3].at(-1)
[1].concat([2, [3]], 4)
[NaN].includes(NaN)
[NaN].indexOf(NaN)
[1, 2, 1].lastIndexOf(1)
[1, null, , 2].join('-')
[1, 2, 3].slice(1)
[1, 2].toString()
${'String.raw`a\\n${one}`'}
Math.fround(0.1)
Math.clz32(1)
Math.imul(0x7fffffff, 3)
Math.sqrt(-1)`));

// Values of the kinds veslint models, as expressions.
const strings = [`''`, `'a'`, `'abc'`, `' aB1 '`, `'12'`, `'0x1F'`, `'-1.5e3'`, `'Σ'`, `'😀x'`];
const numbers = ['0', '-0', '1', '-1', '1.5', '255', 'NaN', 'Infinity', '-Infinity', '2 ** 31', '1e21', '0.1'];
const primitives = ['undefined', 'null', 'true', 'false', ...numbers, ...strings, '1n', '-5n', '0n', 'Symbol.iterator'];
const objects = [
  '[]',
  '[1, 2, 3]',
  `['b', , 'a']`,
  '[[1, [2, [3]]]]',
  `[null, undefined, NaN, 0, '0', false]`,
  '{}',
  `{ a: 1, b: 'x' }`,
  `{ length: 2, 0: 'p', 1: 'q' }`,
  '/a/g',
  `new Map([[1, 'one'], ['k', [2]]])`,
  `new Set([1, 'a', 1])`,
];
const iterators = ['new Map().keys()', `new Set([1]).values()`, '[1, 2].entries()'];
const builtins = ['String', 'Math', 'JSON', 'Map', 'Symbol'];
const values = [...primitives, ...objects, ...builtins];
// What veslint does not model.
const boxed = [`new String('str')`, 'new Number(7)', 'new Boolean(false)', 'Object(1n)', 'Object(Symbol.iterator)'];
const dateValues = ['new Date(86400000)', 'new Date(NaN)'];
const symbols = [`Symbol.for('k')`];
const prototypes = ['Array.prototype', 'Object.prototype', 'String.prototype', 'Number.prototype', 'Function.prototype', 'RegExp.prototype', `'x'.slice`];
const pairs = ['undefined', 'null', 'true', '0', '1', 'NaN', `''`, `'a'`, `'1'`, '1n', 'Symbol.iterator', '[2]', '{}', 'new Set([1])', 'String'];
const paren = code => (/^[A-Za-z_$][\w.$]*$|^\[.*\]$|^'[^']*'$/.test(code) ? code : `(${code})`);
// What veslint does not model, under its limit, and what it models now (no limit: ''): the objects
// of primitives and the symbols of Symbol.for (as an object key, the symbol-key limit).
const unmodelled = [
  ['', boxed],
  ['date', dateValues],
  ['', symbols],
  ['builtin-property', prototypes],
];
// Strings with a surrogate without its pair: a V string cannot hold them, veslint's values can.
const loneSurrogates = [String.raw`'\ud800'`, String.raw`'a\udc00b'`];
// each adds a statement for each modelled value and, if `all`, under its limit for each other one.
const each = (make, all = false) => {
  add(values.map(make));
  if (!all) return;
  add(loneSurrogates.map(make));
  for (const [name, list] of unmodelled) limit_or_core(name, () => add(list.map(make)));
};

// Operators.
for (const operator of ['typeof', 'void', '!', '-', '+', '~']) each(v => `${operator} ${paren(v)}`, ['typeof', '+'].includes(operator));
add('delete record.k', 'delete list[0]', 'delete (1, 2)');
const binary = ['==', '!=', '===', '!==', '<', '<=', '>', '>=', '<<', '>>', '>>>', '+', '-', '*', '/', '%', '**', '|', '^', '&'];
// Every pair of values for some operators, and a few pairs for the ones that work like them.
const allPairs = ['==', '===', '<', '>=', '<<', '>>>', '+', '-', '/', '%', '**', '&'];
const fewer = ['null', '1', `'a'`, '1n', '[2]', '{}'];
for (const operator of binary) {
  const operands = allPairs.includes(operator) ? pairs : fewer;
  const bitwise = ['<<', '>>', '|', '^', '&'].includes(operator);
  for (const a of operands) {
    for (const b of operands) add(`${paren(a)} ${operator} ${paren(b)}`);
  }
  if (['==', '<', '+', '-'].includes(operator)) {
    for (const [name, list] of unmodelled) {
      limit_or_core(name, () => add(list.slice(0, 2).flatMap(v => [`${paren(v)} ${operator} 1`, `'1' ${operator} ${paren(v)}`, `${paren(v)} ${operator} ${paren(v)}`])));
    }
  }
}
for (const operator of ['&&', '||', '??', 'in', 'instanceof']) {
  for (const a of pairs) for (const b of ['undefined', `'a'`, 'String', 'unknownName', '(1n + 1)']) add(`${paren(a)} ${operator} ${b}`);
}
const bigints = ['0n', '1n', '-1n', '5n', '-6n', '64n', '-64n', '12345678901234567890n', '-12345678901234567891n'];
for (const operator of ['+', '-', '*', '/', '%', '**', '<', '==']) {
  // A power of more than 32 bits is a RangeError, except of 0, 1 and -1.
  for (const a of bigints) for (const b of operator === '**' ? bigints.slice(0, 7) : bigints) add(`${paren(a)} ${operator} ${paren(b)}`);
}
add('5n ** 12345678901234567890n', '(-6n) ** 12345678901234567890n');
// The shift and bitwise operators work on infinite two's complement; `>>` rounds toward minus
// infinity; a shift by a negative amount goes the other way.
for (const operator of ['<<', '>>', '&', '|', '^']) {
  for (const a of bigints) for (const b of bigints.slice(0, 7)) add(`${paren(a)} ${operator} ${paren(b)}`);
}
add('0n ** 12345678901234567890n', '1n ** 12345678901234567890n', '(-1n) ** 12345678901234567891n', '(-1n) ** 12345678901234567890n', '(-1n) ** 0n');
add('-5n >> 1n', '-5n >> 100n', '5n >> 100n', '-1n >> 12345678901234567890n', '1n >> 12345678901234567890n', '-5n << -1n', '5n << 0n', '0n << 12345678901234567890n', '1n << 12345678901234567890n', '1n << 1000n', '(1n << 1000n) >> 999n');
add('-1n & 255n', '-256n | 15n', '-7n ^ -8n', '12345678901234567890n & -12345678901234567891n', '-12345678901234567891n | 12345678901234567890n', '(2n ** 64n) ^ -1n', '(2n ** 70n - 1n) & -(2n ** 65n)');
limit('bigint-size', () => add('(2n ** 70000n) > 0n', '(1n << 70000n) > 0n', '(3n ** 50000n) % 7n', '(-1n << 65536n) < 0n'));
add(bigints.map(v => `${paren(v)} >>> 1n`), bigints.map(v => `~${paren(v)}`), bigints.map(v => `-${paren(v)}`), '2n ** 4294967296n', '2n ** -1n', '1n / 0n', '1n % 0n');
each(v => `${paren(v)} ? 1 : 2`);
each(v => `\`<\${${v}}>\``, true);
each(v => `[...${paren(v)}]`, true);
each(v => `({ ...${paren(v)} })`);
add(values.filter(v => v !== 'Symbol.iterator').map(v => `({ [${v}]: 1 })`));
add(loneSurrogates.map(v => `({ [${v}]: 1 })`), String.raw`({ '\ud800': 1, '\ud801': 2 })`, String.raw`({ '\ud800': 1, ['\ud800']: 2, '\ufffd': 3 })`, String.raw`({ ['\ud800']: 1 })['\ud800']`, String.raw`({ ['\ud800']: 1 })['\ufffd']`, String.raw`Object.keys({ ['\ud800a']: 1 })`, String.raw`Object.entries({ '\udc00': 1 })`, String.raw`({ ...{ '\ud800': 1 } })`, String.raw`({ ['\ud83d' + '\ude00']: 1 })`, String.raw`Object.keys({ '\ud83d\ude00': 1, '😀': 2 })`);
for (const [name, list] of unmodelled) limit_or_core(name === '' ? 'symbol-key' : name, () => add(list.map(v => `({ [${v}]: 1 })`)));
each(v => `String.raw\`a\${${v}}b\\n\``);

// Property reads.
const keys = [
  `'length'`, `'constructor'`, `'toString'`, `'valueOf'`, `'name'`, '0', `'1'`, '-1', '1.5', `'size'`, `'source'`, `'flags'`, `'global'`, `'lastIndex'`,
  `'unicodeSets'`, `'description'`, `'at'`, `'a'`, `'get'`, `'has'`, `'keys'`, `'values'`, `'entries'`, `'next'`, `'missing'`, '[0]', `['size']`, `['source']`, '{}', 'null', '1n',
];
const notBuiltin = v => !builtins.includes(v);
for (const key of keys) {
  add(values.filter(notBuiltin).map(v => `${paren(v)}[${key}]`));
  if ([`'length'`, `'constructor'`, `'toString'`, '0'].includes(key)) {
    add(loneSurrogates.map(v => `${v}[${key}]`));
    for (const [name, list] of unmodelled) limit_or_core(name, () => add(list.map(v => `${paren(v)}[${key}]`)));
  }
  limit('builtin-property', () => add(builtins.map(v => `${v}[${key}]`)));
  add(iterators.map(v => `${paren(v)}[${key}]`));
}
add(iterators.flatMap(v => [`typeof ${paren(v)}`, `!${paren(v)}`, `+${paren(v)}`, `${paren(v)} + ''`, `[...${paren(v)}]`, `({ ...${paren(v)} })`, `${paren(v)}()`, `${paren(v)}?.()`, `String(${v})`, `Object.keys(${v})`, `Array.of(...${paren(v)})`, `new Set(${v})`, `Object(${v})`]));
add(iterators.flatMap(v => [`${paren(v)}?.x`, `${paren(v)}?.[0]`, `new Map([${v}])`]));
limit('symbol-key', () => {
  for (const key of ['Symbol.iterator', 'Symbol.toStringTag', 'Symbol.toPrimitive']) add(values.map(v => `${paren(v)}[${key}]`));
});
// `__proto__` of a primitive is its prototype object; of an object, a getter eslint-utils does not
// allow.
limit('builtin-property', () => add(values.filter(v => primitives.includes(v)).map(v => `${paren(v)}.__proto__`)));
add(values.filter(v => !primitives.includes(v)).map(v => `${paren(v)}.__proto__`));
limit('builtin-property', () => add(values.map(v => `${paren(v)}.prototype`)));
each(v => `${paren(v)}?.x`);
each(v => `${paren(v)}?.[0]`);
each(v => `${paren(v)}?.()`);
each(v => `${paren(v)}()`);

// Every own property of every builtin object that an expression names. veslint knows the
// static members of the builtin functions and the methods of the values; the prototype objects
// and the properties of the methods are a limit.
const expressible = name => !name.includes('%') && !name.startsWith('TypedArray');
limit('builtin-property', () => {
  for (const object of builtinObjects) {
    const name = builtinName(object);
    if (!expressible(name)) continue;
    for (const key of Reflect.ownKeys(object)) {
      add(typeof key === 'symbol' ? `${name}[${symbolName(key)}]` : /^[A-Za-z_$][\w$]*$/.test(key) ? `${name}.${key}` : `${name}[${JSON.stringify(key)}]`);
    }
  }
  add(`'a'.slice.length`, `'a'.slice.name`, `'a'.slice.call`, `'a'.slice.prototype`, `[].concat.length`, `Int8Array.from`, `Int8Array.from.name`, `Function.prototype.name`, `typeof Function.prototype`, `String.toString`, `String.constructor`, `String.call`, `Math.max.name`, `map.get.name`, `set.has.length`);
});
add(`isPrototypeOf`, `record.isPrototypeOf`, `isPrototypeOf === record.isPrototypeOf`, `list.isPrototypeOf === 'a'.isPrototypeOf`, `map.isPrototypeOf === isPrototypeOf`, `record.hasOwnProperty === isPrototypeOf`);
add(`''.trimLeft === ''.trimStart`, `Number.parseInt === parseInt`, `new Set().keys === new Set().values`, `'a'.slice === 'b'.slice`, `[].concat === ''.concat`, `map.get === new Map().get`, `map.keys === set.keys`);

// Calls of every function eslint-utils calls, Math aside: its functions have statements of their
// own, and rules/js_math_test.v checks the transcendental ones against V8 on millions of arguments.
const limitOf = name => {
  if (name === 'Date' || name === 'Date.parse') return 'date';
  return '';
};
const stringArgs = ['', '0', '1', '-1', 'NaN', `'a'`, `'b', 1`, '1, 2', '-2, 5', 'undefined, 1', 'Infinity', `'1'`, 'null', '{}', '[1]', '/a/', 'Symbol.iterator', '1n', `'B', -Infinity`, '2, 1', `'', 2`, 'new Set()'];
const stringReceivers = [`'abcabc'`, `' aB1 '`, `'😀b'`];
const arrayArgs = ['', '0', '1', '-1', 'NaN', `'a'`, `'b', 1`, '1, 2', '-2, 5', 'undefined, 1', 'Infinity', 'null', '[1]', '2, -1', 'NaN, 1', 'new Map()', 'Symbol.iterator', '1n, 1n'];
const callbackArgs = ['Boolean', 'String', 'Number', 'isNaN', 'Array.isArray', 'Number.isFinite', 'parseInt', 'Object', `''.includes, 'a1NaN'`, '1', ''];
const arrayReceivers = ['[]', `[1, 2, 'a', NaN, 1]`, `['b', , 'a', undefined, null]`, '[[1, [2, [3, [4]]]], 0]', `[0, '', 'x', [], {}]`];
const generalArgs = [...values, `'a', 'b'`, '1, 2', `'x', 16`, 'undefined, 2', '[1, 2], [1, 2]', 'NaN, NaN', '0, -0', `'%E4%F6%FC'`, `'a b&c=d/é😀;?:@#'`, `'2020-01-01T00:00:00Z'`];
// Fewer of them for the functions veslint does not evaluate.
const fewArgs = ['undefined', 'null', 'true', '1', '-1.5', `''`, `'abc'`, `'a b&c=d/é😀;?:@#'`, `'%E4%F6%FC'`, `'2020-01-01T00:00:00Z'`, '1n', 'Symbol.iterator', '[1, 2, 3]', '{}', 'String', `'a', 'b'`, '65, 0x1f600'];
for (const name of callAllowedNames) {
  if (name.startsWith('Math.')) continue;
  limit_or_core(limitOf(name), () => {
    if (name.startsWith('String.prototype.')) {
      const method = name.slice('String.prototype.'.length);
      for (const receiver of stringReceivers) add(stringArgs.map(args => `${receiver}.${method}(${args})`));
    } else if (name.startsWith('Array.prototype.')) {
      const method = name.slice('Array.prototype.'.length);
      const callback = /^Array\.prototype\.(every|filter|find|findIndex|some)$/.test(name);
      for (const receiver of callback ? arrayReceivers.slice(1, 3) : arrayReceivers) add((callback ? callbackArgs : arrayArgs).map(a => `${receiver}.${method}(${a})`));
    } else if (/\.prototype\./.test(name)) {
      const [owner, method] = name.split('.prototype.');
      const receivers = owner === 'Map' ? ['map', 'new Map()', 'new Map(map)', 'set', 'record'] : owner === 'Set' ? ['set', 'new Set()', `new Set('aab')`, 'map', 'list'] : ['255', '0.5', '-1.5e-7', '1e21', 'NaN', '-0', '123.456', '1 / 3'];
      const args = owner === 'Number' ? ['', '0', '1', '2', '16', '36', '37', '1.9', '-1', '100', '101', 'NaN', 'Infinity', 'undefined', `'8'`, 'null', '1n'] : ['', '1', `'k'`, `'a'`, 'NaN', '0', '-0', '[2]', 'undefined'];
      for (const receiver of receivers) add(args.map(a => `${paren(receiver)}.${method}(${a})`));
    } else if (name === 'Object') {
      const boxes = args => !/^(undefined|null|\[|\{|\/|new )/.test(args) && !builtins.includes(args);
      add(generalArgs.filter(args => !boxes(args)).map(args => `Object(${args})`), 'Object()', 'Object`a${1}`');
      add(generalArgs.filter(boxes).map(args => `Object(${args})`));
    } else {
      // String.raw(String) reads the `length` of String.raw, a property of a builtin method.
      const readsMethodLength = args => name === 'String.raw' && args === 'String';
      add((limitOf(name) === '' ? generalArgs : fewArgs).filter(args => !readsMethodLength(args)).map(args => `${name}(${args})`), `${name}()`, `${name}\`a\${1}\``);
      if (name === 'String.raw') limit('builtin-property', () => add(`String.raw(String)`));
    }
  });
  if (!/\.prototype\./.test(name)) {
    // `new` of a function that is not a constructor throws; Date is a limit.
    const constructed = name === 'Date' ? 'date' : '';
    limit_or_core(constructed, () => add(`new ${name}()`, `new ${name}([[1, 2]])`, `new ${name}(null)`, `new ${name}`));
    limit_or_core(constructed, () => add(`new ${name}(1)`, `new ${name}('a')`));
    // As a callback, with three arguments; Date.parse's values depend on the time zone.
    limit_or_core(name === 'Date.parse' ? 'date' : '', () => add(`[0, 'a', null].filter(${name})`));
  }
}
function limit_or_core(name, fill) {
  if (name === '') fill();
  else limit(name, fill);
}
// An object of a primitive, a Date or a symbol of Symbol.for as the argument of each function.
for (const [name, list] of unmodelled.slice(0, 3)) {
  for (const f of ['String', 'Number', 'Boolean', 'Object', 'Object.keys', 'Array.isArray', 'isNaN', 'parseInt', 'RegExp', 'Array.of', 'Object.is']) {
    limit_or_core(name, () => add(list.map(v => `${f}(${v})`)));
  }
  limit_or_core(name, () => add(list.map(v => `'abc'.concat(${v})`), list.map(v => `[1].includes(${v})`), list.map(v => `new Set([${v}]).size`), list.map(v => `new Map([[${v}, 1]]).size`)));
}
add('Object.freeze()', 'Object.freeze(1, 2)', 'Object.seal(list)', 'Object.preventExtensions(record)', 'Object.isFrozen(Object.freeze({}))', 'new Object.freeze(list)', 'Object.freeze?.(list)', `list.concat?.(3)`, `null?.concat(3)`, `list.missing?.(3)`, `list.missing(3)`, `(list.concat)(3)`, `(list?.concat)(3)`, `(list?.concat)?.(3)`, `(null?.concat)?.(3)`);
// What eslint-utils does not call either.
add(`Object.assign({}, record)`, `Object.fromEntries([['a', 1]])`, `Object.getOwnPropertyNames(record)`, `JSON.stringify(record)`, `'abc'.toLocaleUpperCase()`, `'ABC'.toLocaleLowerCase()`, `'abc'.localeCompare('b')`, `'abc'.repeat(2)`, `'abc'.split('')`, `'abc'.replace('a', 'b')`, `'abc'.match(/a/)`, `['a', 'b'].map(String)`, `[1, 2].reverse()`, `[1, 2].reduce(Math.max)`, `[3, 1].sort()`, `[1, 2].forEach(String)`, `[1, [2]].flatMap(String)`, `[1, 2].findLast(Boolean)`, `[1, 2].toReversed()`, `Number.isInteger(1)`, `Number.isSafeInteger(1)`, `Symbol()`, `Symbol('a')`, `Date.now()`, `Date.UTC(2020)`, `({}).toString()`, `({}).hasOwnProperty('a')`, `true.toString()`, `1n.toString()`, `/a/.toString()`, `/a/.test('a')`, `/a/.exec('a')`, `Array(3)`, `new Array(3)`, `Array.from('ab')`, `new Function('return 1')`, `(() => 1)()`, `(function () {})`, `class {}`, `new Klass()`, `declared()`, `this`, `import.meta`, `one++`, `one += 1`, `one = 5`, `[one, text] = [1, 'a']`, `one!`, `<any>one`, `one as const`, `(one)`, `text satisfies unknown`, `list<number>`, `map.set(1, 2)`, `map.delete(1)`, `map.forEach(String)`, `set.add(1)`, `set.union(set)`, `set.isSubsetOf(set)`, `Map.groupBy([1], String)`, `new WeakMap()`, `new WeakSet()`, `new Promise(String)`, `new Int8Array(2)`, `new ArrayBuffer(2)`, `new Proxy({}, {})`, `Reflect.ownKeys(record)`, `new Symbol()`, `new BigInt(1)`, `new parseInt('1')`, `new isNaN(1)`, `new Array.isArray([])`, `new ''.slice(1)`, `new (new Map().get)(1)`);

// Map and Set, the iterators and Object.*.
add(split(String.raw`map
set
map.size
set.size
map['size']
set['size']
map[['size']]
map.size()
Map.prototype.size
Set.prototype.size
map.get(1)
map.get('k')
map.get(NaN)
map.get('missing')
map.get()
map.has(-0)
map.has(NaN)
set.has(0)
set.has(-0)
set.has('a')
set.has()
map.get
map.constructor
set.constructor === Set
map.toString
map.hasOwnProperty
map.missing
map.set
map.getOrInsert
set.union
set.keys
[...map]
[...map.keys()]
[...map.values()]
[...map.entries()]
[...set]
[...set.keys()]
[...set.values()]
[...set.entries()]
[...map][0] === [...map][0]
[...map][1][1] === map.get('k')
new Map(map).get('k') === map.get('k')
new Map(map).get('k')
new Map([[1, 2], [1, 3]])
new Map([[1, 2], [1, 3]]).size
new Map([[-0, 'z']])
new Map([[-0, 'z']]).keys()
new Map([[0, 'a'], [-0, 'b']])
new Map([[NaN, 'a'], [NaN, 'b']])
new Map([[[], 'a'], [[], 'b']]).size
new Map([[list, 'a'], [list, 'b']]).size
new Map([['1', 'a'], [1, 'b'], [1n, 'c'], [true, 'd'], [null, 'e'], [undefined, 'f']]).size
new Map([1])
new Map(['ab'])
new Map([[1]])
new Map([[]])
new Map([[, 1]])
new Map([[1, , 3]])
new Map([{ 0: 'k', 1: 'v' }])
new Map([{}])
new Map([/a/])
new Map([map])
new Map([String])
new Map([[1, 2], 3])
new Map([null])
new Map(5)
new Map('ab')
new Map({})
new Map(null)
new Map(undefined)
new Map(undefined, 1)
new Map()
new Map
new Map(Object.entries({ a: 1, b: 2 }))
new Map(Object.entries({ a: 1, b: 2 })).get('b')
new Map(new Map([[1, 2]]).entries())
new Map([[1, 2]].values())
new Map([[1, 2]].entries())
new Map(set.entries())
new Map(map.keys())
new Map(...[[[1, 2]]])
new Map([...map, ['x', 'y']]).size
new Map([[1, 2]], ...list)
new Map(unknownName)
new Map([[unknownName, 1]])
new Map(1n + 1)
Map()
Set()
Map([])
Set([])
new Set('hello')
new Set('😀a')
new Set([NaN, NaN, 0, -0, '0', [], []])
new Set([NaN, NaN, 0, -0, '0', [], []]).size
new Set([, 1, undefined])
new Set(5)
new Set({})
new Set(null)
new Set()
new Set
new Set(new Set([1, 2]).values())
new Set(set)
new Set(map)
new Set(map.keys())
new Set(map.values())
new Set([[1, 2]].entries())
new Set([1, 2].keys())
new Set([...set, 2])
new Set(list).has(2)
new Set([1, 2]).size + new Map([[1, 2]]).size
new Set([list]).has(list)
new Set([[1]]).has([1])
typeof map
typeof set
typeof map.keys()
typeof set.values()
typeof map.get
!map
map ? 1 : 2
map + ''
map + 1
+map
-set
String(set)
String(map)
${'`${map}${set}`'}
String(map.keys())
String(map.entries())
String(set.values())
String(set.entries())
String([].keys())
[1].entries() + ''
[map, set] + ''
[map.keys()].join()
map == map
map === map
new Map() == new Map()
set == '[object Set]'
set === set
map.keys() == map.keys()
Object.keys(map)
Object.values(map)
Object.entries(set)
Object.keys(map.keys())
({ ...map })
({ ...set, a: 1 })
({ ...[].keys() })
[map].includes(map)
[set].indexOf(set)
Array.isArray(map)
Array.of(...set)
Array.of(...map.keys())
Array.of(...[1, 2].values())
String.fromCharCode(...new Set([65, 66, 65]))
[...[1, 2].entries()]
[...[1, , 3].keys()]
[...[1, , 3].values()]
[...[].values()]
[...[1, 2].values(), ...new Set([3])]
[...list.entries()][1][1]
[1, 2].keys()
[1, 2].values()
[1, , 3].entries()
[1, 2].keys(1)
'abc'.keys
[...map.keys()].includes('k')
[...map.values()].indexOf('one')
[...set].join('-')
[...set].length
[...new Set('aabbc')].join('')
[...new Map([['a', 1]])][0]
[...new Map([['a', 1]])][0][0]
written
written.get('a')
written.size
added
added.has(1)
cleared.size
assigned
map.keys === new Map().keys
map.entries()
set.entries()
null?.size
map?.size
map?.get(1)
map.get?.(1)
map.missing?.(1)
(map.get)(1)
(map?.get)(1)
new Map([[1, 2]])?.get(1)`));
add('set.values().constructor', '[].keys().missing', '[].keys().length', 'new Map([[1].keys()])', 'new Map([map.keys()]).size');
// What iterators have: next, the helpers of %IteratorPrototype% and Object.prototype.
add('[].keys().next === [1].values().next', 'map.keys().next === set.values().next', '[].keys().map === map.keys().map', '[].keys().take', 'set.values().toArray', '[].keys().hasOwnProperty', '[].keys().next()', '`${[].keys()}`');
add(split(String.raw`Object.keys(list)
Object.keys(['x', 'y'])
Object.values(['x', 'y'])
Object.entries(['x', 'y'])
Object.keys([1, , 3])
Object.values([1, , 3])
Object.entries([1, , 3])
Object.keys('ab')
Object.values('ab')
Object.entries('ab')
Object.keys('😀')
Object.keys('')
Object.keys(1)
Object.values(true)
Object.entries(1n)
Object.keys(Symbol.iterator)
Object.keys(regexp)
Object.values(regexp)
Object.keys(String)
Object.keys(Math)
Object.entries(JSON)
Object.keys(Array.isArray)
Object.keys(null)
Object.keys(undefined)
Object.keys()
Object.values()
Object.entries(null)
Object.keys(unknownName)
Object.keys(record)
Object.values(record)
Object.entries(record)
Object.entries({ b: 1, a: 2, 1: 3, 0: 4 })
Object.keys({})
Object.keys(list, record)
Object.keys(Object.keys(record))
Object.entries(Object.entries(record))
Object.keys(list) === Object.keys(list)
Object.entries(list)[0] === Object.entries(list)[0]
Object.keys(list).length
Object.keys(list).includes('1')
Object.values('ab').join('')
Object.entries(list)[1][0]
Object()
Object(null)
Object(undefined)
Object(list)
Object(list) === list
Object(record).k
Object(regexp)
Object(map).size
Object(String)
Object(Math)
Object({}, 1)
new Object()
new Object(null)
new Object(list)
new Object(record).k
typeof Object()
Object.keys(Object())
Object.is(NaN, 0 / 0)
Object.is(0, -0)
Object.is(-0, -0)
Object.is(list, list)
Object.is('a', 'a')
Object.is(1n, 1n)
Object.is(map, map)
Object.is(new Map(), new Map())
Object.is()
Object.is(undefined)
Object.is(null, undefined)
Object.is(Symbol.iterator, Symbol.iterator)
Object.is(String, String)
Object.isFrozen(1)
Object.isFrozen('a')
Object.isFrozen(null)
Object.isFrozen()
Object.isFrozen(list)
Object.isFrozen([])
Object.isFrozen({})
Object.isFrozen(regexp)
Object.isFrozen(map)
Object.isFrozen(String)
Object.isFrozen(Math)
Object.isFrozen(Symbol.iterator)
Object.isFrozen(Object.freeze(list))
Object.isSealed(null)
Object.isSealed(1n)
Object.isSealed(record)
Object.isSealed(set)
Object.isSealed(Object.seal(record))
Object.isSealed(JSON)
Object.isExtensible(1)
Object.isExtensible()
Object.isExtensible(regexp)
Object.isExtensible(Math)
Object.isExtensible(list)
Object.isExtensible(map.keys())
Object.isExtensible(Object.preventExtensions(record))
Object.isExtensible(String)`));
add(`Object(1)`, `Object('a')`, `Object(true)`, `new Object('a')`, `new Object(1)`, `Object('ab').length`, `Object.keys(Object('ab'))`, `typeof Object(1)`, `Object(1) + 1`, `new String('ab')[0]`, `new Number(5).toFixed(1)`, `new Boolean(false) ? 1 : 2`, `[...new String('ab')]`, `new String('a') == 'a'`);
// The objects of primitives: own indexes and length for a String object, the methods of the
// prototype of the primitive (thisNumberValue takes a Number object), valueOf before toString but
// for the hint `string`, a symbol's object converted to its symbol, and identity.
add(`new String('a') === new String('a')`, `Object(1) === Object(1)`, `new Number(1) == new Number(1)`, `new String('ab').slice(1)`, `new String('ab').toString()`, `new Number(255).toString(16)`, `new Boolean(true).toString()`, `\`\${new Number(2)}\``, `String(new Number(2))`, `new Number(2) + ''`, `String(new Boolean(false))`, `new Boolean(false) + 1`, `Object(1n) + 1n`, `String(Object(1n))`, `Object(Symbol.iterator) == Symbol.iterator`, `Object(Symbol.iterator).description`, `Object(Symbol.iterator).toString`, `String(Object(Symbol.iterator))`, `[...Object(1)]`, `({ ...new String('ab') })`, `Object.entries(new String('ab'))`, `new String(Symbol.iterator)`, `new Number(1n)`, `new Number('0x10')`, `new Boolean()`, `new String()`, `new String('ab').length`, `new String('ab')[2]`, `new String('ab').constructor`, `Object(1).constructor`, `new String('a') < new String('b')`, `Object.keys(new Number(1))`, `new Set([new String('a'), new String('a')]).size`, `new Map([[Object(1), 2]]).get(Object(1))`, `[Object(1)].includes(Object(1))`, `Object(Object(1)) === Object(1)`, `Array.isArray(new String('a'))`, `({ [new String('k')]: 1 })`, `record[new String('k')]`);

// The other limits.
add(`Symbol.for('a') === Symbol.for('a')`, `Symbol.for('a').description`, `String(Symbol.for('a'))`, `typeof Symbol.for('a')`, `Symbol.keyFor(Symbol.iterator)`, `Symbol.keyFor(Symbol.for('a'))`);
// The registry: one symbol per key (the key is ToString of the argument), never a well-known one.
add(`Symbol.for('a') === Symbol.for('b')`, `Symbol.for('Symbol.iterator') === Symbol.iterator`, `Symbol.for('Symbol.iterator').description === Symbol.iterator.description`, `Symbol.for() === Symbol.for('undefined')`, `Symbol.for(1) === Symbol.for('1')`, `Symbol.for({})`, `Symbol.for([1, 2]).description`, `Symbol.for(Symbol.iterator)`, `Symbol.for(1n).description`, String.raw`Symbol.for('\ud800').description`, String.raw`Symbol.keyFor(Symbol.for('\ud800'))`, `Symbol.keyFor('a')`, `Symbol.keyFor()`, `Symbol.keyFor(Symbol.for(''))`);
add(`[Symbol.for('a')].includes(Symbol.for('a'))`, `[Symbol.for('a')].indexOf(Symbol.for('a'))`, `new Map([[Symbol.for('a'), 1]]).get(Symbol.for('a'))`, `new Set([Symbol.for('a'), Symbol.for('a'), Symbol.iterator]).size`, `Object.is(Symbol.for('a'), Symbol.for('a'))`, `Symbol.for('a') == Symbol.for('a')`, `Symbol.for('a') != Symbol.iterator`, `Symbol.for('a').toString()`, `Symbol.for('a').constructor`, `!Symbol.for('a')`, `[Symbol.for('a'), Symbol.iterator]`, `Symbol.for('x').description.length`);
add(`Symbol.iterator.description`, `Symbol.iterator.toString`, `Symbol.iterator.constructor`, `Symbol.iterator === Symbol.iterator`, `Symbol.iterator === Symbol.asyncIterator`, `Symbol.dispose.description`, `typeof Symbol.iterator`, `Symbol.iterator + ''`, `[Symbol.iterator] + ''`, `Symbol.for(Symbol.iterator)`, `Symbol.keyFor('a')`);
limit('symbol-key', () =>
  add(
    `({ [Symbol.iterator]: 1 })`, `({ [Symbol.iterator]: 1, a: 2 }).a`, `({ [Symbol.iterator]: 1 })[Symbol.iterator]`, `list[Symbol.iterator]`, `list[Symbol.iterator] === list.values`, `[][Symbol.unscopables].flat`, `text[Symbol.iterator].name`,
    `Math[Symbol.toStringTag]`, `map[Symbol.toStringTag]`, `map[Symbol.iterator] === map.entries`, `map[Symbol.iterator]()`, `set[Symbol.iterator]()`, `list[Symbol.iterator]()`, `regexp[Symbol.match].name`, `RegExp[Symbol.species]`, `RegExp[Symbol.species]('a')`,
    `[...{ length: 2, 0: 'a', [Symbol.iterator]: [].values }]`, `({ [Symbol.toStringTag]: 'Tag' }) + ''`, `({ [Symbol.toPrimitive]: Boolean }) + 1`, `[].concat({ [Symbol.isConcatSpreadable]: true, length: 1, 0: 'a' })`, `'abc'.startsWith({ [Symbol.match]: false })`, `Symbol.iterator[Symbol.toPrimitive]`,
  ),
);
add(
  `({ __proto__: null })`, `({ __proto__: null }).toString`, `({ __proto__: [1, 2] }).length`, `({ __proto__: { a: 1 }, b: 2 }).a`, `({ __proto__: 5 })`, `({ __proto__: record }).k`, `({ '__proto__': record }).k`, `({ ['__proto__']: null })`, `({ ['__proto__']: 1 })`, `({ ['__proto__']: record }).k`,
  `({ a: 1, ['__proto__']: 1 }).a`, `({ __proto__ })`, `({ __proto__, a: 1 }).a`, `({ ...{ ['__proto__']: record } }).k`, `[].__proto__`, `({}).__proto__`, `record.__proto__`, `String.__proto__`, `map.__proto__`,
  `({ __proto__: map }).size`, `({ __proto__: regexp }).source`, `Object.keys({ __proto__: { a: 1 }, b: 2 })`, `({ __proto__: null }) + ''`, `({ __proto__: null, __proto__: 1 })`,
);
limit('builtin-property', () => add(`'a'.__proto__`, `'a'.__proto__ === String.prototype`, `(1).__proto__`, `'a'['__proto__']`));
// The prototype of an object literal: what it inherits, what Object.prototype.toString and the
// array methods read through it, and a `__proto__` that is an own property once the object no
// longer inherits the setter.
add(`({ __proto__: [1, 2] }).join()`, `[...{ __proto__: [1, , 3] }]`, `({ __proto__: [1, 2], f: [].join }).f('-')`, `({ __proto__: { __proto__: null } }).toString`, `({ __proto__: { __proto__: record } }).k`, `({ __proto__: map }) + ''`, `({ __proto__: Math }) + ''`, `({ __proto__: regexp }).lastIndex`, `({ __proto__: regexp }).test`, `({ __proto__: String }).fromCharCode(65)`, `({ __proto__: Math }).PI`, `({ __proto__: [1, 2] }).constructor`, `({ __proto__: null }).__proto__`, `({ __proto__: null, __proto__: record }).__proto__ === record`, `({ ...{ __proto__: null, __proto__: record } }).k`, `({ __proto__: new String('ab') }).length`, `({ __proto__: [].keys() }).next`, `Object.is({ __proto__: record }, { __proto__: record })`, `({ __proto__: { valueOf: Boolean } }) + 1`);
add(`null.__proto__`, `undefined?.__proto__`, `unknownName.__proto__`);
add(`[, 1].every(Boolean)`, `[0, 1].find(Boolean)`, `[3, 4].findIndex(Number.isFinite)`, `['1', '2', '3'].find(parseInt)`, `[[1], 2].filter(Array.isArray)`, `[1].some([].includes, [1])`, `[1].some(Symbol)`, `[1].every(Number.isInteger)`, `[...set].filter(Boolean)`, `[...map.values()].some(Array.isArray)`);
// Callbacks: `this` is the second argument; find and findIndex visit the holes; the truth of what
// the callback returns, also of the ones whose value veslint does not model.
add(`[, 0, , 1].find(Boolean)`, `[, 0].findIndex(isNaN)`, `[, ''].some(isNaN)`, `['a', 'b'].filter(''.includes, 'xa')`, `[1, 2].every(set.has, set)`, `[1, 'k'].filter(map.has, map)`, `[0, 1].filter(Object)`, `[0, ''].every(Date)`, `[0, ''].some(Array)`, `[Symbol.iterator].some(Symbol)`, `[2 ** 53].every(Number.isSafeInteger)`, `[0.5].some(Number.isInteger)`, `[1].filter(Object.freeze)`, `[[1], {}].filter(Object.keys)`, `[null].some(Object.keys)`, `[1].some(isPrototypeOf)`, `[[]].some(isPrototypeOf)`);
limit('builtin-property', () => add(`[1].some(Array.prototype.includes, [1])`));
limit('native-call', () => add(`[1].some(JSON.stringify)`, `[[1]].every(Array.from)`, `[{}].find(Object.getPrototypeOf)`, `[[1]].some(Reflect.ownKeys)`, `({ toString: JSON.stringify }) + ''`, `({ f: [].toString, join: JSON.stringify }).f()`, `({ toString: [].toString, join: [].join, length: 1, 0: 'x' }) + ''`, `({ valueOf: ''.at }) + 1`));
add(`[1, 2].every(1)`, `[].every(1)`, `[].some()`, `[1].filter(unknownName)`, `[1].find(() => true)`, `[1].some(declared)`, `[1].every(Map)`);
add(`[1, [2, [3, [4]]]].flat(-1)`, `[1, [2, , [3]]].flat('2')`, `[[1, [2]], 'ab'].flat(Infinity)`, `[...map].flat()`);
add(['', '2', 'NaN', '-Infinity', '1.9', 'null', `'x'`, '[1]', 'Symbol.iterator', '1n'].map(depth => `[1, [2, [3, [4]]]].flat(${depth})`));
add(`[[], [[]], , [, 1]].flat(Infinity)`, `[new Set([1]), [map], 'ab'].flat()`, `list.flat() === list`, `[[1], [2]].flat().length`, `[].flat()`);
const texts = [`'Å'`, `'ﬁ'`, `'é'`, `'한글'`, `'ẛ̣'`, `'a'`, String.raw`'\ud800'`];
for (const form of ['', `'NFC'`, `'NFD'`, `'NFKC'`, `'NFKD'`, 'undefined']) add(texts.map(t => `${t}.normalize(${form})`));
add(`'x'.normalize('NFD')`, `'é'.normalize('NFD').length`, `'ﬁ'.normalize('NFKC') === 'fi'`);
add(`'a'.normalize('x')`, `'a'.normalize(null)`, `'a'.normalize(Symbol.iterator)`, `'é'.normalize('nfc')`);
add(`(5).toString()`, `(255).toString(16)`, `(0.5).toString(2)`, `(-255).toString(36)`, `(1e21).toString(36)`, `(2 ** 53 + 2).toString(3)`, `(0.1).toString(3)`, `NaN.toString(2)`, `(1.5).toString(undefined)`, `(1 / 3).toString(10)`, `Number.MAX_VALUE.toString(2).length`);
add(`(1).toString(1)`, `(1).toString(37)`, `(1).toString(1n)`, `(1).toFixed(101)`, `(1).toPrecision(0)`, `(1).toExponential(-1)`);
// V8's DoubleToRadixCString: fraction digits up to the precision of the double, rounded to even
// with a carry, and zeros for the integer digits beyond it.
const radixValues = ['0.1', '0.7', '1 / 3', '2 / 3', '1 / 7', 'Math.PI', '-Math.E', '1e-10', '123456789.123', '0.9999999999999999', '99.99999999999999', '1 - 2 ** -53', '2 ** 60 + 2 ** 8', '1e300', '-1e-300', '5e-324', '2 ** -1022', '4.35', '255.5', '35', '36', '-0'];
for (const radix of ['2', '3', '7', '8', '16', '36']) add(radixValues.map(v => `(${v}).toString(${radix})`));
add(`(10).toString(10.5)`, `(1).toString(2.9)`, `(31).toString('16')`, `(31).toString([16])`, `(1).toString(-0)`, `(1).toString(NaN)`, `(1).toString(null)`, `(1).toString(Infinity)`, `Infinity.toString(16)`, `(-Infinity).toString(2)`, `(5e-324).toString(2).length`, `Number.MAX_VALUE.toString(36)`, `(1).toString(Symbol.iterator)`);
add(`encodeURIComponent('a b')`, `encodeURI('é/😀')`, `decodeURIComponent('%C3%A9')`, `decodeURI('%2F%20')`, `escape('é ü')`, `unescape('%u00e9%20')`, `encodeURIComponent()`, `decodeURI(list)`);
add(`decodeURI('%')`, String.raw`encodeURI('\ud800')`, `decodeURIComponent('%C0%80')`, `encodeURIComponent(Symbol.iterator)`);
// Encode and Decode: surrogates, the reserved set, each UTF-8 length and the URIErrors.
add(String.raw`encodeURIComponent('😀')`, String.raw`encodeURIComponent('\ud83d')`, String.raw`encodeURIComponent('\ude00x')`, String.raw`encodeURIComponent('\ud83dx')`, `encodeURI(";/?:@&=+$,#-_.!~*'()")`, `encodeURIComponent(";/?:@&=+$,#-_.!~*'()")`, String.raw`encodeURI('\x00\x7f\x80߿ࠀ￿')`, `encodeURI(1n)`, `encodeURI([1, 'a b'])`, `encodeURI({})`, `encodeURIComponent(String)`);
add(['%F0%9F%98%80', '%f0%9f%98%80', '%E2%82%AC', '%E2%82', '%E2%82%2', '%E2%82%AC%', '%ED%A0%80', '%F4%90%80%80', '%F4%8F%BF%BF', '%E0%80%80', '%E0%A0%80', '%80', '%FF', '%F8%80%80%80%80', '%C3%28', '%C3%', 'a%2', '%zz', '%23%3B%2f%41', '%25', '%E2%2582%AC'].flatMap(s => [`decodeURIComponent('${s}')`, `decodeURI('${s}')`]));
// Annex B: `%uXXXX` is only tried after `%u`, and a `%` that does not start an escape stays.
add([String.raw`\x00\x7f\xffĀ￿+-./@*_~`, '%u', '%u12', '%u1234', '%u12345', '%U1234', '%4', '%41%', '%u0025%41', '%%41', '%uD83D%uDE00', '%uzz00', '%u00zz'].map(s => `${s.startsWith('%') ? 'unescape' : 'escape'}('${s}')`));
add(`escape(String)`, `escape(unescape('%u0100%FF'))`, `unescape(escape('😀 a'))`);
add(`String.fromCodePoint(65, 0x1f600)`, `String.fromCodePoint()`, `String.fromCodePoint('65', [66], true, null)`);
add(`String.fromCodePoint(0x110000)`, `String.fromCodePoint(-1)`, `String.fromCodePoint(1.5)`, `String.fromCodePoint(1n)`, `String.fromCharCode(0x1f600, -1, 65.9, '66')`);
add(`String.fromCodePoint(0x10ffff)`, `String.fromCodePoint(0xd800, 0xdc00)`, `String.fromCodePoint(-0)`, `String.fromCodePoint(NaN)`, `String.fromCodePoint(Infinity)`, `String.fromCodePoint('0x41')`, `String.fromCodePoint([])`, `String.fromCodePoint({})`, `String.fromCodePoint(65, Symbol.iterator)`);
add('String.raw({ raw: ["a", "b", "c"] }, 1, 2, 3)', `String.raw({ raw: 'abc' }, 0, 1)`, 'String.raw({ raw: [] }, 1)');
add('String.raw({}, 1)', 'String.raw()', 'String.raw`\\u{zz}${1}\\n`', 'String.raw`a${Symbol.iterator}`', 'String.raw`a${map}${[...set]}`');
add(`String.raw({ raw: { length: 3, 0: 'x', 2: 'z' } }, 1, 2)`, `String.raw({ raw: ['a', 'b'] })`, `String.raw({ raw: ['a'] }, Symbol.iterator)`, `String.raw({ raw: ['a', 'b'] }, Symbol.iterator)`, `String.raw({ raw: { length: -1 } })`, `String.raw({ raw: { length: 2.9, 0: 1, 1: 2 } }, 0)`, `String.raw({ raw: 12 })`, `String.raw({ raw: null })`, `String.raw({ raw: 'ab' }, [1, 2], {})`, `String.raw('abc')`, `String.raw({ raw: ['a', 'b'] }, map)`, `String.raw({ raw: [[1], , 'c'] }, 2, 3)`, `String.raw({ raw: String })`);
limit('long-value', () => add(`String.raw({ raw: { length: 1100000 } }).length`));
add(`isPrototypeOf(1)`, `list.isPrototypeOf(list)`, `'a'.isPrototypeOf('a')`, `map.isPrototypeOf(map)`);
limit('builtin-property', () => add(`Object.prototype.isPrototypeOf(list)`, `Array.prototype.isPrototypeOf(list)`));
add(`isPrototypeOf(list)`, `isPrototypeOf({})`, `null.isPrototypeOf(1)`);
add(`record.isPrototypeOf({})`, `(1).isPrototypeOf([])`, `isPrototypeOf(null)`, `isPrototypeOf(Symbol.iterator)`, `String.isPrototypeOf(String)`, `Math.isPrototypeOf(Math)`, `set.isPrototypeOf(new Set().values())`);
// Math.f16round: ties to even, the subnormals, the largest finite value and no double rounding
// through binary32.
add(['', '0', '-0', 'NaN', 'Infinity', '-Infinity', '1', '-1', '1.337', '0.1', '65504', '65519.99', '65520', '-65520', '1e10', '2 ** -24', '2 ** -25', '2 ** -25 + 2 ** -60', '3 * 2 ** -25', '2 ** -14', '2 ** -14 - 2 ** -25', '1 + 2 ** -11', '1 + 3 * 2 ** -11', '1 + 2 ** -11 + 2 ** -40', '5e-324', `'2.5'`, `'x'`, 'null', '[]', '1n', 'Symbol.iterator', '2049', '2051', '4095'].map(v => `Math.f16round(${v})`));
// The transcendental functions of Math (rules/js_math.v): ToNumber of the argument, then V8's own
// function; atan2 and hypot with their arities.
const transcendental = ['acos', 'acosh', 'asin', 'asinh', 'atan', 'atanh', 'cbrt', 'cos', 'cosh', 'exp', 'expm1', 'log', 'log1p', 'log2', 'log10', 'sin', 'sinh', 'tan', 'tanh'];
add(['', '0', '-0', '1', '-1', '0.5', '2', '10', 'NaN', 'Infinity', '-Infinity', '1e300', `'3'`, '[2]', 'null', 'true', '1n', 'Symbol.iterator'].flatMap(v => transcendental.map(name => `Math.${name}(${v})`)));
add(`Math.atan2(1, 1)`, `Math.atan2(-0, -1)`, `Math.atan2()`, `Math.atan2(1)`, `Math.atan2(1n, 1)`, `Math.atan2(1, Symbol.iterator)`, `Math.atan2(Infinity, -Infinity)`);
add(`Math.hypot()`, `Math.hypot(3, 4)`, `Math.hypot(-0)`, `Math.hypot(1, 2, 3)`, `Math.hypot(1, 2, 3, 4, 5)`, `Math.hypot(NaN, Infinity)`, `Math.hypot('3', [4])`, `Math.hypot(1, 1n)`, `Math.hypot(Symbol.iterator, NaN)`, `Math.hypot(1e308, 1e308)`);
add(`Math.sin(Math.PI)`, `Math.cos(Math.PI) === -1`, `Math.exp(1) === Math.E`, `Math.log(Math.E)`, `Math.tan(Math.PI / 4)`, `Math.cbrt(-27)`, `Math.log10(1000)`, `Math.log2(8)`);
add(`({ f: ''.trim }).f()`, `({ f: ''.charAt }).f(1)`, `[''.at][0](0)`, `({ f: [].join, length: 2, 0: 'x', 1: 'y' }).f('-')`, `[[].join][0]()`, `({ f: [].includes, length: 1, 0: 1 }).f(1)`, `({ f: (5).toFixed }).f`, `({ f: Array.isArray }).f([])`, `({ f: String }).f(1)`, `[parseInt][0]('12')`, `({ get: map.get }).get`);
// The String methods take any receiver but undefined and null, through ToString, except toString;
// the Array methods take an object with a length (holes where an index is missing): concat does
// not spread it, and toString calls its join or gives Object.prototype.toString.
add(`({ f: ''.padEnd }).f(18, '-')`, `({ f: ''.at }).f(-1)`, `({ f: ''.toString }).f()`, `[''.slice][0]()`, `({ f: ''.includes }).f('ject')`, `({ f: ''.normalize, toString: 1 }).f()`);
add(`({ f: [].at, length: 3, 1: 'b' }).f(-2)`, `({ f: [].concat }).f(1, [2])`, `({ f: [].toString }).f()`, `({ f: [].toString, join: [].join, length: 1, 0: 'z' }).f()`, `({ f: [].toString, join: 1 }).f()`, `({ f: [].keys, length: 2 }).f()`, `({ f: [].every, length: 2, 0: 1, 1: 0 }).f(Boolean)`, `({ f: [].slice, length: 3, 0: 'a', 2: 'c' }).f()`, `({ f: [].join, length: -1 }).f()`, `({ f: [].join, length: '2', 0: 1 }).f()`, `({ f: [].indexOf, length: 2, 1: NaN }).f(NaN)`, `({ f: [].flat, length: 2, 0: [1, [2]], 1: 3 }).f(Infinity)`, `({ f: [].find, length: 2 }).f(isNaN)`);
add(`({ f: (5).toFixed }).f(1)`, `({ get: map.get }).get(1)`, `({ has: set.has }).has(1)`, `[map.get][0](1)`, `({ keys: map.keys }).keys()`);
add(`({ valueOf: Boolean }) + 1`, `String({ valueOf: Boolean, toString: Number })`, `+{ valueOf: Boolean }`, `({ toString: String }) + ''`, `[{ toString: Boolean }] + ''`, `({ toString: 1 }) + ''`, `({ valueOf: 1 }) + 1`, `({ toString: Number }) == 0`);
// OrdinaryToPrimitive: valueOf first, toString first for a string; eslint-utils joins a template
// literal with `+`, so its parts are converted as `+` converts them.
add('`${{ valueOf: Boolean, toString: Number }}`', `[{ valueOf: Boolean }] + ''`, `({ valueOf: String }) < 'a'`, `({ toString: [].join }) + ''`, `({ toString: Boolean, valueOf: 1 }) == false`, `String({ toString: Object })`, `({ valueOf: Array.of }) + 1`, `({ toString: ''.trim }) + ''`, `({ toString: ''.trim }).toString()`, `({ f: [].toString, join: [].toString }).f()`, `({ f: [].toString, join: ''.trim }).f()`, `({ [{ toString: Number }]: 1 })`, `record[{ toString: () => 'k' }]`, `({ valueOf: Symbol.for }) + ''`, `-{ valueOf: Number.isNaN }`);
add(`({ valueOf: 1, toString: 2 }) + ''`, `({ toString: Object }) + ''`, `({ valueOf: 1 })`, `({ valueOf: 1 }).valueOf`, `typeof { toString: 1 }`, `!{ valueOf: Boolean }`);
add(String.raw`'\ud800'.length`, String.raw`'\ud800' + 'a'`, String.raw`'😀b\ud800'.at(-1)`, String.raw`'\ud83d' + '\ude00'`, String.raw`['\udc00'].join()`, String.raw`'a\ud800'.endsWith('\ud800')`);
add(String.raw`'\ud83d\ude00'.length`, String.raw`'\u{1f600}'.codePointAt(0)`, String.raw`'\ud83d\ude00' === '😀'`);
limit('long-value', () => add(`'ab'.padEnd(1100000).length`, `'ab'.padStart(2 ** 21, 'xy').length`, `({ f: [].includes, length: 2 ** 21 }).f(1)`));
add(`'a'.padEnd(Infinity)`, `'a'.padEnd(2 ** 31)`, `''.padEnd(2 ** 20).length`, `'a'.padEnd(2 ** 31, '')`);
limit('depth', () => add(`deep${chainLength}`, `deep105`, `[deep102]`));
add('deep90', 'deep95', `[deep90, deep90].length`);
limit('date', () =>
  add(
    split(String.raw`new Date(0)
new Date(0) < new Date(1)
+new Date(5)
new Date(5) - 1
Number(new Date(5))
typeof new Date()
!new Date()
new Date() ? 1 : 2
new Date() === new Date()
new Date('2020-01-01T00:00:00Z')
new Date('2020-01-01')
new Date('2020-01-01T00:00:00')
new Date(2020, 0)
new Date(NaN, 0)
new Date(NaN) + ''
String(new Date(NaN))
String(new Date(5))
new Date(5) + 1
${'`${new Date(5)}`'}
new Date()
Date()
typeof Date()
Date.parse('2020-01-01T00:00:00Z')
Date.parse('2020-01-01T00:00:00.123+05:30')
Date.parse('2020-01-01')
Date.parse('2020-01-01T00:00:00')
Date.parse('Jan 1 2020')
Date.parse('1 January 2020 00:00:00 GMT')
Date.parse('foo')
Date.parse('')
Date.parse()
new Date(new Date(5))
new Date(8.64e15 + 1)
new Date(true)
new Date(null)
new Date(undefined)
new Date('5')
new Date(1, 2, 3, 4, 5, 6, 7)
new Date(0).getTime
new Date(0).constructor === Date
Object.keys(new Date(0))
new Date(5) == 5
new Date(NaN) == 'Invalid Date'
[new Date(NaN), 1].join()
isNaN(new Date(NaN))
new Map([[new Date(0), 1]]).size`),
  ),
);
add(`new Date(1n)`, `new Date(Symbol.iterator)`, `new Date(2020, 1n)`, `Date.now()`, `Date.UTC(2020, 0)`, `new Date(0).getTime()`, `new Date(0).toISOString()`, `'abc'.toLocaleUpperCase`, `(1234.5).toLocaleString()`, `[1, 2].toLocaleString()`);

// Exceptions inside the evaluation: the whole value is not static.
add(split(String.raw`nullKey
[1, (1n + 1)] || 2
true || (1n + 1)
false && (1n + 1)
(1n + 1) || true
null ?? (1n + 1)
1 ? 2 : (1n + 1)
0 ? 2 : (1n + 1)
void (1n + 1)
typeof (1n + 1)
((1n + 1), 2)
(unknownName, 2)
[unknownName] + (1n + 1)
({ [unknownName]: (1n + 1) })
null.x
undefined[0]
null?.x
(null)?.x.y.z
(null)?.[unknownName]
null?.[1n + 1]
unknownName?.x
null?.x()
null?.(1n + 1)
undefined?.(unknownName)
(null as any)?.x
null!.x
(void 0)?.x[0]
(null?.x).y
(null?.x)?.y
null?.x?.y
one?.toFixed(1)
one?.toFixed?.(1)
one.missing?.(1)
one.missing?.x.y
text?.[0]
text?.length.toFixed
Symbol.iterator + ''
${'`${Symbol.iterator}`'}
Symbol.iterator < 1
+Symbol.iterator
1n + 1
1n < 1
1n == 1
1n === 1
+1n
BigInt(1.5)
BigInt('x')
BigInt(undefined)
BigInt('0x10') + BigInt(' 12 ') + BigInt(true)
[].at(Symbol.iterator)
[1].join(Symbol.iterator)
[Symbol.iterator].join()
[[Symbol.iterator]].toString()
String([Symbol.iterator])
new RegExp('a', 'x')
RegExp('[')
RegExp(Symbol.iterator)
'abc'.startsWith(/a/)
'abc'.includes(/a/)
'abc'.endsWith(regexp)
'abc'.indexOf(/a/)
'/a/'.includes(/a/)
regexp[['source']]
regexp[['flags']]
map[['get']]`));
// Constants that refer to each other. eslint-utils evaluates the initializer of a constant at
// every reference, so it recurses until JavaScript's stack overflows, and its try/catch, which is
// around the whole getStaticValue, answers null: nothing that was already evaluated counts. A
// reference that `||`, `&&`, `??`, `?:`, a sequence or `void` does not evaluate is never reached.
declare(String.raw`const forkA = [forkB, forkB];
const forkB = forkA + forkA;
const tri1 = [tri2, tri2];
const tri2 = { a: tri3, b: tri3 };
const tri3 = ${'`${tri1}${tri1}`'};
const selfArray = [selfArray];
const selfPair = [selfPair, selfPair];
const selfObject = { a: selfObject, b: selfObject };
const selfTemplate = ${'`${selfTemplate}${selfTemplate}`'};
const selfCall = String(selfCall) + String(selfCall);
const selfSpread = [...selfSpread, ...selfSpread];
const selfKey = { [selfKey]: 1, [selfKey]: 2 };
const selfMember = selfMember.x + selfMember.y;
const selfNew = new Map([[selfNew, selfNew]]);
const selfTest = selfTest ? selfTest : selfTest;
const selfUnary = -selfUnary - -selfUnary;
const reachedOr = false || reachedOr;
const reachedAnd = true && reachedAnd;
const reachedNullish = null ?? reachedNullish;
const reachedThen = true ? reachedThen : 'else';
const unreachedOr = true || unreachedOr;
const unreachedAnd = false && unreachedAnd;
const unreachedNullish = 1 ?? unreachedNullish;
const unreachedThen = false ? unreachedThen : 'else';
const unreachedElse = true ? 'then' : unreachedElse;
const unreachedSequence = (unreachedSequence, 5);
const unreachedVoid = void unreachedVoid;
const cycleMethod = ['abc'];
cycleMethod[cycleName]();
const cycleName = cycleName2 + cycleName2;
const cycleName2 = cycleName + cycleName;
const usedAsName = [1, 2];
const namedBy = ['abc'];
namedBy[usedAsName.length]();
const usedInCall = [1, 2];
const namedByCall = ['abc'];
namedByCall[String(usedInCall.length)]();
const deepPush0 = 'push';
${Array.from({ length: chainLength }, (_, i) => `const deepPush${i + 1} = deepPush${i};`).join('\n')}
const deepAt0 = 'at';
${Array.from({ length: chainLength }, (_, i) => `const deepAt${i + 1} = deepAt${i};`).join('\n')}`);
for (const name of ['forkA', 'forkB', 'tri1', 'tri2', 'tri3', 'selfArray', 'selfPair', 'selfObject', 'selfTemplate', 'selfCall', 'selfSpread', 'selfKey', 'selfMember', 'selfNew', 'selfTest', 'selfUnary', 'reachedOr', 'reachedAnd', 'reachedNullish', 'reachedThen', 'cycleMethod', 'cycleName']) {
  expect(name, false);
}
for (const name of ['usedAsName', 'namedBy', 'usedAsName.length']) expect(name, false);
for (const name of ['usedInCall', 'namedByCall']) expect(name, true);
for (const name of ['unreachedOr', 'unreachedAnd', 'unreachedNullish', 'unreachedThen', 'unreachedElse', 'unreachedSequence', 'unreachedVoid']) expect(name, true);

// What an exception does to the expressions around it. `throwing` are expressions whose
// evaluation throws in eslint-utils (in veslint, some of them are also something it does not
// evaluate); `notStatic` are expressions for which eslint-utils answers null without an
// exception. Alone both are "not static"; the difference shows where eslint-utils goes on after a
// null: the name of a method called on a constant (hasMutationInProperty).
const throwing = [
  // Operators.
  '1n + 1', '1n * 1.5', '+1n', '1n >>> 0n', '1n / 0n', '2n ** -1n', '-Symbol.iterator', '+Symbol.iterator', '~Symbol.iterator', `Symbol.iterator + ''`, 'Symbol.iterator * 2', 'Symbol.iterator < 1', '`${Symbol.iterator}`',
  // A property of undefined or null.
  'null.x', 'undefined[0]', '({}).missing.x', 'null.x()', 'undefined.x()', '[1].missing.x()',
  // A getter that throws, read to call it.
  'String.arguments()',
  // Functions of callAllowed that throw.
  `BigInt('x')`, 'BigInt(1.5)', 'BigInt(undefined)', 'BigInt(Symbol.iterator)', `new RegExp('[')`, `RegExp('(')`, `RegExp('a', 'x')`, 'RegExp(Symbol.iterator)', '(1).toFixed(101)', '(1).toPrecision(0)',
  '(1).toExponential(-1)', '(1).toFixed(1n)', `'a'.padEnd(Infinity)`, `'abc'.startsWith(/a/)`, `'a'.concat(Symbol.iterator)`, `'a'.at(1n)`, '[1].join(Symbol.iterator)', '[Symbol.iterator].join()', '[1].at(1n)', '[1].slice(Symbol.iterator)',
  'Number(Symbol.iterator)', 'parseInt(Symbol.iterator)', 'isNaN(1n)', 'isFinite(Symbol.iterator)', 'String.fromCharCode(1n)', 'Object.keys(null)', 'Object.entries()', 'Math.max(1n)', 'Math.abs(Symbol.iterator)', 'Map()', 'Set([])',
  // Constructors that throw, and functions of callAllowed that are not constructors.
  'new Map([1])', 'new Map(5)', 'new Set(5)', 'new Set({})', 'new BigInt(1)', `new parseInt('1')`, 'new isNaN()', `new ''.slice()`, 'new Array.isArray([])', 'new Object.keys({})',
  // What is not iterable, spread.
  '[...1]', '[...{}]', '[...null]', '[...Math]', 'Array.of(...1)',
  // A symbol in a template of String.raw.
  'String.raw`${Symbol.iterator}`',
  // The same in what veslint does not evaluate.
  `'a'.normalize('x')`, 'String.fromCodePoint(-1)', `decodeURI('%')`, `Symbol.keyFor('a')`, '(1).toString(1)', '[1].every(1)', '[1].flat(Symbol.iterator)', 'Symbol.for(Symbol.iterator)', 'new Date(Symbol.iterator)', 'new String(Symbol.iterator)',
  'isPrototypeOf({})', `({ valueOf: 1, toString: 2 }) + 1`, '({ [{ __proto__: null }]: 1 })', '1n << 1',
];
const notStatic = [
  // No value.
  'unknownName', 'ambient', 'uninitialized', 'reassigned', 'declared', 'Klass', 'destructured', 'this', 'import.meta', '(() => 1)', '(function () {})', 'class {}', 'one++', 'one += 1', '1 in [1]', '[] instanceof Array', 'delete ({ k: 1 }).k',
  '{ m() {} }', '{ get g() { return 1; } }',
  // A call of what is not a function of callAllowed is never made.
  'undefined()', 'null()', '(5)()', `'a'()`, '[1].missing()', `({ k: 'v' }).k()`, '/a/.source()', 'declared()', `'a'.repeat(-1)`, `'a'.repeat(2)`, `'abc'.split('')`, '[1].map(String)', '[2, 1].sort()', 'Symbol()', `Symbol('a')`, 'JSON.parse("{")',
  'Date.now()', 'Object.assign({}, null)', 'Number.isInteger(1)', '({}).toString()', '/a/.test(1)', 'new Array(-1)', 'new Klass()', 'new Symbol()', 'new Promise(1)', 'new Function("(")', 'JSON`a`', 'unknownName`a`',
  // A property that is not static is not read.
  'null[unknownName]', 'undefined[ambient]',
  // A getter eslint-utils does not read.
  '/a/.unicodeSets', `/a/[['source']]`, '({}).__proto__', '[].__proto__', 'String.arguments', 'String.caller', 'RegExp.lastMatch', `RegExp['$1']`, `new Map()[['size']]`, 'new Map().keys().constructor',
  // The same getters, read to call what they give.
  '/a/.unicodeSets()', 'new Map().size()', '({}).__proto__()', 'RegExp.lastMatch()', `/a/[['flags']]()`,
];
const around = x => [
  x, `[${x}, 1]`, `[1, ${x}]`, `${paren(x)} || 1`, `1 || ${paren(x)}`, `0 && ${paren(x)}`, `null ?? ${paren(x)}`, `true ? 1 : ${paren(x)}`, `false ? 1 : ${paren(x)}`, `(${x}, 1)`, `(1, ${x})`, `void ${paren(x)}`, `typeof ${paren(x)}`, `({ a: ${x} })`,
  `\`<\${${x}}>\``, `unknownName + ${paren(x)}`, `${paren(x)} + unknownName`,
];
for (const x of [...throwing, ...notStatic]) add(around(x));
// The name of a method called on a constant: an exception there ends the evaluation of the
// constant, a name that is not static does not make the call a mutation. (The names below do not
// read another constant directly: hasMutationInProperty also takes `a[b.c]()` for a call on `b`,
// and evaluating `b` then evaluates `b.c`, which evaluates `b`: see usedAsName.)
let methods = 0;
const method = (name, isStatic, limitName = '', callLimit = limitName) => {
  const id = `method${methods++}`;
  declare(`const ${id} = ['abc'];\n${id}[${name}]();`, callLimit);
  limit_or_core(limitName, () => {
    expect(id, isStatic);
    expect(`${id}[0]`, isStatic);
  });
};
for (const x of throwing) method(x, false);
for (const x of notStatic) method(x, true);
// Static names: of a mutating method or not.
for (const x of [`'push'`, `'sort'`, `'copyWithin'`, "`pu${'sh'}`", `['push'][0]`, `'PUSH'.toLowerCase()`, `new Map([[1, 'pop']]).get(1)`, `[...new Set(['shift'])][0]`, 'deepPush90']) method(x, false);
for (const x of [`'at'`, `'slice'`, '1', 'null', 'undefined', `['push']`, `'Push'`, `new Set(['push'])`, 'deepAt90']) method(x, true);
// The call itself is one veslint does not evaluate (a symbol key); the constant is static.
method('Symbol.iterator', true, '', 'symbol-key');
// Names made by calls of the functions static_builtins.v and unicode_normalization.v evaluate, and
// by callbacks.
method('String.fromCodePoint(112, 117, 115, 104)', false);
method(`'pu'.normalize() + 'sh'`, false);
method(`'a'.normalize()`, true);
method(`unescape('%70%75%73%68')`, false);
method('String.fromCodePoint(97)', true);
method('(255).toString(16)', true);
method(`[0, 'push'].find(Boolean)`, false);
method(`[0, 'at'].find(Boolean)`, true);
// Names veslint does not evaluate: the constant is not static for it, which is eslint-utils'
// answer when the name is the one of a mutating method.
method(`deepPush${chainLength}`, false);
method(`Symbol.for('push')`, true, '', 'symbol-key');
method(`deepAt${chainLength}`, true, 'depth');
// More than 100 levels: not static, whatever is around.
limit('depth', () => add(`[deep${chainLength}, 1]`, `deep${chainLength} || 1`, `deep${chainLength} + unknownName`, `typeof deep${chainLength}`, `({ a: deep${chainLength} })`));
add(`1 || deep${chainLength}`, `(deep${chainLength}, 2)`, `void deep${chainLength}`, `true ? 1 : deep${chainLength}`, `unknownName + deep${chainLength}`);

// ---------------------------------------------------------------------------------------------
// The probe: a rule that asks getStaticValue for every expression statement.

const allDeclarations = declarations + moreDeclarations;
const source = `${allDeclarations}${cases.map(({ code }) => `(${code});`).join('\n')}\n`;
const tagRuns = list => {
  const out = [];
  for (const item of list) {
    if (out.length > 0 && out.at(-1)[1] === item) out.at(-1)[0]++;
    else out.push([1, item]);
  }
  return out;
};

const hex = text => Array.from({ length: text.length }, (_, i) => text.charCodeAt(i).toString(16)).join(',');
const iteratorTags = new Map(
  [[][Symbol.iterator](), new Map()[Symbol.iterator](), new Set()[Symbol.iterator]()].map(iterator => [
    Object.getPrototypeOf(iterator),
    iterator[Symbol.toStringTag],
  ]),
);
const wrappers = [
  [String.prototype, String.prototype.valueOf],
  [Number.prototype, Number.prototype.valueOf],
  [Boolean.prototype, Boolean.prototype.valueOf],
  [BigInt.prototype, BigInt.prototype.valueOf],
  [Symbol.prototype, Symbol.prototype.valueOf],
];
const serializeNumber = n => (Object.is(n, -0) ? '-0' : String(n));
const serializeKey = key => (typeof key === 'symbol' ? serialize(key, 0) : hex(key));
// serialize writes a value like stv_test_serialize of rules/static_value_test.v: u(ndefined),
// null, b(oolean), n(umber), s(tring, as UTF-16 units), i (BigInt), y (a well-known symbol) or
// yr (a registered one), f (a builtin function) or ns (another builtin object) with its name,
// a[…] (array, h: a hole), o{…} (object; o^proto{…} when its prototype is not Object.prototype),
// r (RegExp), m{…} (Map), e[…] (Set), d (Date), w(…) (the object of a primitive) and t (an
// iterator, with what is left of it).
function serialize(value, depth) {
  if (depth > 6) return '…';
  switch (typeof value) {
    case 'undefined':
      return 'u';
    case 'boolean':
      return `b:${value}`;
    case 'number':
      return `n:${serializeNumber(value)}`;
    case 'string':
      return `s:${hex(value)}`;
    case 'bigint':
      return `i:${value}`;
    case 'symbol': {
      const key = Symbol.keyFor(value);
      return key === undefined ? `y:${symbolName(value)}` : `yr:${hex(key)}`;
    }
  }
  if (value === null) return 'null';
  const builtin = builtinName(value);
  if (builtin !== undefined) return `${typeof value === 'function' ? 'f' : 'ns'}:${builtin}`;
  if (typeof value === 'function') return '?:function';
  const proto = Object.getPrototypeOf(value);
  const extra = Reflect.ownKeys(value).length;
  if (Array.isArray(value) && proto === Array.prototype) {
    const items = Array.from({ length: value.length }, (_, i) => (i in value ? serialize(value[i], depth + 1) : 'h'));
    return `a[${items.join(';')}]`;
  }
  if (proto === RegExp.prototype && extra === 1) return `r:${hex(value.source)}/${value.flags}`;
  if (proto === Map.prototype && extra === 0) {
    return `m{${[...value].map(([k, v]) => `${serialize(k, depth + 1)}=>${serialize(v, depth + 1)}`).join(';')}}`;
  }
  if (proto === Set.prototype && extra === 0) return `e[${[...value].map(v => serialize(v, depth + 1)).join(';')}]`;
  if (proto === Date.prototype && extra === 0) return `d:${serializeNumber(value.getTime())}`;
  for (const [prototype, valueOf] of wrappers) {
    if (proto !== prototype) continue;
    try {
      return `w(${serialize(valueOf.call(value), depth + 1)})`;
    } catch {
      // An ordinary object with that prototype.
    }
  }
  if (iteratorTags.has(proto) && extra === 0) {
    try {
      return `t:${iteratorTags.get(proto)}[${[...value].map(v => serialize(v, depth + 1)).join(';')}]`;
    } catch {
      return `t:${iteratorTags.get(proto)}!`;
    }
  }
  const properties = Reflect.ownKeys(value).map(key => {
    const descriptor = Object.getOwnPropertyDescriptor(value, key);
    if (!('value' in descriptor)) throw new Error('an accessor in a value');
    return `${serializeKey(key)}=${serialize(descriptor.value, depth + 1)}`;
  });
  const prototype = proto === Object.prototype ? '' : proto === null ? '^null' : `^${serialize(proto, depth + 1)}`;
  return `o${prototype}{${properties.join(';')}}`;
}

function probe() {
  const { Linter } = reference('eslint');
  const parser = reference('@typescript-eslint/parser');
  const { getStaticValue } = reference(eslintUtilsPath);
  const found = [];
  const rule = {
    create(context) {
      const globalScope = context.sourceCode.getScope(context.sourceCode.ast);
      return {
        ExpressionStatement(node) {
          const result = getStaticValue(node.expression, globalScope);
          found.push({ line: node.loc.start.line, value: result == null ? 'NULL' : serialize(result.value, 0) });
        },
      };
    },
  };
  const messages = new Linter({ configType: 'flat' }).verify(
    source,
    [{ files: ['**/*.ts'], languageOptions: { parser }, plugins: { probe: { rules: { probe: rule } } }, rules: { 'probe/probe': 'error' } }],
    { filename: 'cases.ts' },
  );
  if (messages.length > 0) {
    throw new Error(`ESLint: ${JSON.stringify(messages[0])} in ${source.split('\n')[messages[0].line - 1]}`);
  }
  return found;
}

if (process.argv[2] === '--probe') {
  process.stdout.write(JSON.stringify(probe()));
} else {
  const environments = [
    { TZ: 'UTC', LC_ALL: 'C' },
    { TZ: 'Asia/Kolkata', LC_ALL: 'es_MX.UTF-8' },
    { TZ: 'America/St_Johns', LC_ALL: 'ja_JP.UTF-8' },
  ];
  const runs = environments.map(env =>
    JSON.parse(
      execFileSync(process.execPath, [import.meta.filename, '--probe'], {
        env: { ...process.env, LANG: env.LC_ALL, ...env },
        maxBuffer: 1 << 28,
        encoding: 'utf8',
      }),
    ),
  );
  const [first] = runs;
  let dependent = 0;
  const lines = first.map((entry, i) => {
    for (const run of runs) {
      if (run.length !== first.length || run[i].line !== entry.line) throw new Error('the runs do not have the same statements');
    }
    if (runs.every(run => run[i].value === entry.value)) return entry;
    dependent++;
    return { line: entry.line, value: 'ENV' };
  });
  const sourceLines = source.split('\n');
  const firstCase = allDeclarations.split('\n').length;
  const tagOfLine = new Map([...declaredTags, ...cases.map((entry, i) => [firstCase + i, entry.tag])]);
  const output = {
    node: process.version,
    eslintUtils: eslintUtilsVersion,
    environments,
    source,
    limits,
    // The functions eslint-utils calls (callAllowed) and the ones it gives the first argument of
    // without calling them (callPassThrough), by name.
    callAllowed: callAllowedNames,
    callPassThrough: callPassThroughNames,
    // The expression statements, in order: the ones of the declarations (their lines), then one
    // per line from `firstCase`. The value of each, and the limit each was written under ('' for
    // none) as runs: a count and the limit.
    declarationLines: lines.filter(entry => entry.line < firstCase).map(entry => entry.line),
    firstCase,
    values: lines.map(entry => entry.value),
    tags: tagRuns(lines.map(entry => tagOfLine.get(entry.line) ?? '')),
  };
  const caseLines = lines.filter(entry => entry.line >= firstCase);
  if (caseLines.length !== cases.length || caseLines.some((entry, i) => entry.line !== firstCase + i)) {
    throw new Error('a case is not one expression statement');
  }
  // What this file says of a statement is what eslint-utils answers.
  for (const [i, { code, isStatic }] of cases.entries()) {
    if (isStatic !== undefined && isStatic !== (caseLines[i].value !== 'NULL')) {
      const declared = allDeclarations.split('\n').find(line => line.startsWith(`${code.split('[')[0]}[`)) ?? '';
      throw new Error(`(${code}) is ${isStatic ? 'not ' : ''}static in eslint-utils ${declared}`);
    }
  }
  fs.writeFileSync(path.join(root, 'tests/static_value_cases.json'), `${JSON.stringify(output)}\n`);
  const nulls = lines.filter(entry => entry.value === 'NULL').length;
  console.error(`${lines.length} statements of ${sourceLines.length} lines: ${nulls} not static, ${dependent} that depend on the environment`);
}
