// prefer-includes: `indexOf` comparisons and `/re/.test(x)` with a plain string.
declare const items: number[];
declare const frozen: readonly string[];
declare const text: string;
declare const bytes: Uint8Array;
declare const maybe: number[] | undefined;
declare const either: string | string[];
declare const anything: any;
declare function count(value: unknown): number;

interface Same {
  indexOf(value: string, from?: number): number;
  includes(value: string, from?: number): boolean;
}
interface Different {
  indexOf(value: string): number;
  includes(value: string, from?: number): boolean;
}
interface WithoutIncludes {
  indexOf(value: string): number;
}
class Box {
  indexOf(value: number): number {
    return value;
  }
  includes(value: number): boolean {
    return value > 0;
  }
}
declare const same: Same;
declare const different: Different;
declare const without: WithoutIncludes;
declare const box: Box;

// Reported: comparisons equivalent to includes().
items.indexOf(1) !== -1;
items.indexOf(1) != -1;
items.indexOf(1) > -1;
items.indexOf(1) >= 0;
items.indexOf(1) === -1;
items.indexOf(1) == -1;
items.indexOf(1) <= -1;
items.indexOf(1) < 0;
items.indexOf(1) !== (-1);
(items.indexOf(1)) !== -1;
items['indexOf'](1) !== -1;
items[`indexOf`](1) !== -1;
maybe?.indexOf(1) !== -1;
frozen.indexOf('a') !== -1;
text.indexOf('a') !== -1;
bytes.indexOf(1) !== -1;
either.indexOf('a') !== -1;
same.indexOf('a') !== -1;
box.indexOf(1) !== -1;
/* 😀 */ items.indexOf(1) !== -1;
// The member may also be an argument of the compared call.
count(items.indexOf) !== -1;
(items.indexOf(1) !== -1) && true;

// Reported: the compared value is a constant (resolved with the scope).
const NOT_FOUND = -1;
items.indexOf(1) !== NOT_FOUND;
items.indexOf(1) === NOT_FOUND;

// Not reported: other comparisons, other methods, or no matching `includes`.
items.indexOf(1) !== 0;
items.indexOf(1) > 0;
items.indexOf(1) === 1;
items.indexOf(1) >= -1;
-1 !== items.indexOf(1);
items.indexOf(1) !== -1n;
items.lastIndexOf(1) !== -1;
items.indexOf(1) + 1;
different.indexOf('a') !== -1;
without.indexOf('a') !== -1;
anything.indexOf('a') !== -1;
items.indexOf!(1) !== -1;

// Reported: a regular expression that is a plain string.
/bar/.test(text);
/bar/u.test(text);
/bar/y.test(text);
/bar/v.test(text);
/a\/b/.test(text);
/\n\t/.test(text);
/😀/u.test(text);
/bar/?.test(text);
/bar/.test(frozen);
/bar/.test(either);

// Reported: a constant regular expression.
const PLAIN = /bar/;
PLAIN.test(text);

// Not reported.
/bar/i.test(text);
/bar/g.test(text);
/ba+r/.test(text);
/a|b/.test(text);
/^a/.test(text);
/a$/.test(text);
/[a]/.test(text);
/(?:)/.test(text);
/bar/.test(text, 1);
/bar/['test'](text);
/bar/.test(1);
/bar/.test(anything);
/bar/.exec(text);
let reassignedRe = /bar/;
reassignedRe = /baz/;
reassignedRe.test(text);
const mutatedRe = /bar/;
mutatedRe.lastIndex = 1;
mutatedRe.test(text);

// A regular expression with a surrogate that has no pair: the string of the fix has that
// surrogate, which is U+FFFD once written in UTF-8.
/\ud800/.test(text);
/a\ud800b/.test(text);
/\udc00\ud800/.test(text);
/😀/.test(text);
/😀/u.test(text);
/\u{d800}/u.test(text);
/\ud800/u.test(text);
