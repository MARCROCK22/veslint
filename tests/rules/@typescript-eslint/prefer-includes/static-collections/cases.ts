// The static values of Map, Set, their iterators and the functions of Object (eslint-utils
// evaluates them): each test is reported only when the value is the expected one.
declare const text: string;
const map = new Map<unknown, unknown>([[1, 'one'], ['k', 'abc'], [NaN, 0]]);
const set = new Set<unknown>(['abc', 1, 'abc', -0]);
new RegExp(map.get('k') === 'abc' ? 'abc' : 'a.c').test(text);
new RegExp(map.get(NaN) === 0 ? 'abc' : 'a.c').test(text);
new RegExp(map.get('missing') === undefined ? 'abc' : 'a.c').test(text);
new RegExp(map.size === 3 ? 'abc' : 'a.c').test(text);
new RegExp(map['size'] === 3 ? 'abc' : 'a.c').test(text);
new RegExp(String(map.has(1)) + map.has('1') === 'truefalse' ? 'abc' : 'a.c').test(text);
new RegExp(set.size === 3 ? 'abc' : 'a.c').test(text);
new RegExp(String(set.has(0)) + set.has(-0) + set.has('0') === 'truetruefalse' ? 'abc' : 'a.c').test(text);
new RegExp([...set].join() === 'abc,1,0' ? 'abc' : 'a.c').test(text);
new RegExp([...map.keys()].join() === '1,k,NaN' ? 'abc' : 'a.c').test(text);
new RegExp([...map.values()].join() === 'one,abc,0' ? 'abc' : 'a.c').test(text);
new RegExp([...map.entries()].join(';') === '1,one;k,abc;NaN,0' ? 'abc' : 'a.c').test(text);
new RegExp([...map].length === 3 ? 'abc' : 'a.c').test(text);
new RegExp([...set.keys()].join() + [...set.values()].join() === 'abc,1,0abc,1,0' ? 'abc' : 'a.c').test(text);
new RegExp([...set.entries()].join(';') === 'abc,abc;1,1;0,0' ? 'abc' : 'a.c').test(text);
new RegExp(String(map) + set === '[object Map][object Set]' ? 'abc' : 'a.c').test(text);
new RegExp(String(map.keys()) + set.values() + [].entries() === '[object Map Iterator][object Set Iterator][object Array Iterator]' ? 'abc' : 'a.c').test(text);
new RegExp(typeof map + typeof set.entries() === 'objectobject' ? 'abc' : 'a.c').test(text);
new RegExp(new Map([[1, 2], [1, 3]]).get(1) === 3 ? 'abc' : 'a.c').test(text);
new RegExp(new Map([[0, 'a'], [-0, 'b']]).size === 1 ? 'abc' : 'a.c').test(text);
new RegExp(new Map(map).get('k') === 'abc' ? 'abc' : 'a.c').test(text);
new RegExp(new Map(Object.entries({ a: 'abc' })).get('a') === 'abc' ? 'abc' : 'a.c').test(text);
new RegExp(new Map([{ 0: 'k', 1: 'v' }] as any).get('k') === 'v' ? 'abc' : 'a.c').test(text);
new RegExp(new Map().size + new Map(null).size + new Set(undefined).size === 0 ? 'abc' : 'a.c').test(text);
new RegExp(new Set('aabbc').size === 3 ? 'abc' : 'a.c').test(text);
new RegExp(new Set([NaN, NaN, 0, -0, '0', [], []]).size === 5 ? 'abc' : 'a.c').test(text);
new RegExp(new Set(map.keys()).has('k') ? 'abc' : 'a.c').test(text);
new RegExp(new Set(map).size === 3 ? 'abc' : 'a.c').test(text);
new RegExp(new Set([5, 6].keys()).has(1) ? 'abc' : 'a.c').test(text);
new RegExp([...[5, 6].keys()].join() === '0,1' ? 'abc' : 'a.c').test(text);
new RegExp([...['x', , 'y'].values()].join() === 'x,,y' ? 'abc' : 'a.c').test(text);
new RegExp([...['x', 'y'].entries()].join(';') === '0,x;1,y' ? 'abc' : 'a.c').test(text);
new RegExp(Array.of(...new Set([1, 1, 2])).length === 2 ? 'abc' : 'a.c').test(text);
new RegExp(String.fromCharCode(...new Set([97, 98, 97, 99])) === 'abc' ? 'abc' : 'a.c').test(text);
new RegExp(map === map ? 'a.c' : 'abc').test(text);
new RegExp([...map.values()][1] as string).test(text);
new RegExp([...new Set(['abc'])][0]).test(text);
new RegExp(Object.keys(['x', 'y']).join() === '0,1' ? 'abc' : 'a.c').test(text);
new RegExp(Object.keys(['x', , 'y']).join() === '0,2' ? 'abc' : 'a.c').test(text);
new RegExp(Object.values('abc').join('-') === 'a-b-c' ? 'abc' : 'a.c').test(text);
new RegExp(Object.entries(['x']).join() === '0,x' ? 'abc' : 'a.c').test(text);
new RegExp(Object.keys(map).length + Object.values(set).length + Object.entries(/a/).length === 0 ? 'abc' : 'a.c').test(text);
new RegExp(Object.keys(1).length + Object.keys(true).length + Object.keys(String).length + Object.keys(Math).length === 0 ? 'abc' : 'a.c').test(text);
new RegExp(Object.keys(Object()).length + Object.keys(Object(null)).length + Object.keys(new Object()).length === 0 ? 'abc' : 'a.c').test(text);
new RegExp(Object(['abc'])[0]).test(text);
new RegExp((new Object({ a: 'abc' }) as { a: string }).a).test(text);
new RegExp(String(Object.isFrozen(1)) + Object.isSealed('a') + Object.isExtensible(null) === 'truetruefalse' ? 'abc' : 'a.c').test(text);
new RegExp(String(Object.isFrozen([])) + Object.isSealed(map) + Object.isExtensible({}) === 'falsefalsetrue' ? 'abc' : 'a.c').test(text);
new RegExp(String(Object.isFrozen(Object.freeze({}))) === 'false' ? 'abc' : 'a.c').test(text);
// For eslint-utils a Map or a Set is what its initializer makes, whatever the code adds to it.
const written = new Map<string, string>();
written.set('a', 'abc');
new RegExp(written.size === 0 ? 'abc' : 'a.c').test(text);
new RegExp(written.get('a') === undefined ? 'abc' : 'a.c').test(text);
// Not static: Map and Set without `new`, what is not iterable, an entry that is not an object,
// the methods eslint-utils does not call, a method without its receiver.
new RegExp(String((Map as any)()) === '' ? 'abc' : 'abd').test(text);
new RegExp(new Map([1] as any).size === 0 ? 'abc' : 'abd').test(text);
new RegExp(new Set(5 as any).size === 0 ? 'abc' : 'abd').test(text);
new RegExp(String(map.forEach(String)) === '' ? 'abc' : 'abd').test(text);
new RegExp(String(set.union(set)) === '' ? 'abc' : 'abd').test(text);
new RegExp(String(Object.keys(null as any)) === '' ? 'abc' : 'abd').test(text);
new RegExp((map?.get)(1) === 'one' ? 'abc' : 'abd').test(text);
new RegExp(map[['size'] as any] === 3 ? 'abc' : 'abd').test(text);
// Values veslint computed where eslint-utils has none or another one: a getter read with a key
// that is not a string, a parenthesized optional chain as the callee, a computed or shorthand
// `__proto__` key (which sets the prototype), and Math.LOG10E.
const __proto__ = 1;
new RegExp(/abc/[['source'] as any] === 'abc' ? 'abc' : 'a.c').test(text);
new RegExp(String((['x']?.concat)('y')) === 'x,y' ? 'abc' : 'a.c').test(text);
new RegExp(Object.keys({ ['__proto__']: 1 }).length === 1 ? 'abc' : 'a.c').test(text);
new RegExp(Object.keys({ __proto__ }).length === 1 ? 'abc' : 'a.c').test(text);
new RegExp(Math.LOG10E - 1.4342944819032518 === -1 ? 'abc' : 'a.c').test(text);
new RegExp(Math.LOG10E === 0.4342944819032518 ? 'abc' : 'a.c').test(text);
// The global isPrototypeOf is Object.prototype's: one function under two names.
new RegExp(isPrototypeOf === ({}).isPrototypeOf ? 'abc' : 'a.c').test(text);
