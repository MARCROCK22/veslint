// Exceptions in the evaluation of a constant: eslint-utils' try/catch is around the whole
// getStaticValue, so one exception makes everything not static. Each test is reported only when
// its regular expression is static.
declare const text: string;
// Constants that refer to each other: the stack overflows.
const forkA: any = [forkB, forkB];
const forkB: any = forkA + forkA;
new RegExp(forkA ? 'abc' : 'abd').test(text);
new RegExp([forkB, 'abc'][1]).test(text);
new RegExp((forkA, 'abc')).test(text);
new RegExp('abc' || forkA).test(text);
new RegExp(typeof forkB === 'string' ? 'abc' : 'abd').test(text);
const selfPair: any = [selfPair, selfPair];
const selfKey: any = { [selfKey]: 'abc', [selfKey]: 'abd' };
const selfText: string = `${selfText}${selfText}`;
new RegExp(selfPair.length === 2 ? 'abc' : 'abd').test(text);
new RegExp(selfKey ? 'abc' : 'abd').test(text);
new RegExp(selfText + 'abc').test(text);
const reachedOr: any = false || reachedOr;
const unreachedOr: any = 'abc' || unreachedOr;
new RegExp(reachedOr).test(text);
new RegExp(unreachedOr).test(text);
// The name of a method called on a constant: where evaluating it throws, the constant is not
// static.
const sum = ['abc'];
sum[1n + 1]();
new RegExp(sum[0]).test(text);
const plus = ['abc'];
plus[+(1n as any)]();
new RegExp(plus[0]).test(text);
const ofNull = ['abc'];
ofNull[(null as any).x]();
new RegExp(ofNull[0]).test(text);
const ofUndefined = ['abc'];
ofUndefined[({} as any).missing.x]();
new RegExp(ofUndefined[0]).test(text);
const bigint = ['abc'];
bigint[BigInt('x') as any]();
new RegExp(bigint[0]).test(text);
const invalid = ['abc'];
invalid[new RegExp('[') as any]();
new RegExp(invalid[0]).test(text);
const range = ['abc'];
range[(1).toFixed(101)]();
new RegExp(range[0]).test(text);
const symbol = ['abc'];
symbol[`${Symbol.iterator as any}`]();
new RegExp(symbol[0]).test(text);
const spread = ['abc'];
spread[[...(1 as any)] as any]();
new RegExp(spread[0]).test(text);
const getter = ['abc'];
getter[(String as any).arguments()]();
new RegExp(getter[0]).test(text);
const constructed = ['abc'];
constructed[new (BigInt as any)(1)]();
new RegExp(constructed[0]).test(text);
const called = ['abc'];
called[(Map as any)()]();
new RegExp(called[0]).test(text);
// A name that is not static, without an exception: the call is not a mutation.
const unknown = ['abc'];
unknown[text]();
new RegExp(unknown[0]).test(text);
const notCalled = ['abc'];
notCalled[(undefined as any)()]();
new RegExp(notCalled[0]).test(text);
const notAllowed = ['abc'];
notAllowed['a'.repeat(-1)]();
new RegExp(notAllowed[0]).test(text);
const notRead = ['abc'];
notRead[/a/.unicodeSets as any]();
new RegExp(notRead[0]).test(text);
const proto = ['abc'];
proto[({} as any).__proto__]();
new RegExp(proto[0]).test(text);
const legacy = ['abc'];
legacy[(RegExp as any).lastMatch()]();
new RegExp(legacy[0]).test(text);
// A static name: of a mutating method or not.
const pushed = ['abc'];
pushed[['push'][0]]();
new RegExp(pushed[0]).test(text);
const read = ['abc'];
read[['at'][0] as 'at'](0);
new RegExp(read[0]).test(text);
// A name veslint does not evaluate (normalize, String.fromCodePoint): here it is the one of a
// mutating method.
const normalized = ['abc'];
normalized[('pu'.normalize() + 'sh') as 'push']();
new RegExp(normalized[0]).test(text);
const fromCodePoint = ['abc'];
fromCodePoint[String.fromCodePoint(112, 117, 115, 104) as 'push']();
new RegExp(fromCodePoint[0]).test(text);
// `a[b.c]()` is also taken for a call on `b`, and evaluating `b` then evaluates `b.c`: `b` is
// never static.
const usedAsName = ['abc'];
const namedBy = ['abc'];
namedBy[usedAsName.length]();
new RegExp(usedAsName[0]).test(text);
new RegExp(namedBy[0]).test(text);
