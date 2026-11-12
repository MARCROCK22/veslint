// A variable is a constant for the rule while nothing writes it after its initializer. In the
// target of a destructuring assignment or of a for-of loop, typescript-eslint's scope manager
// writes every identifier it finds, also those inside the type of an assertion: `typeof b` there
// is a write of `b`. Around a plain assignment target the type is only read.
declare const s: string;
let a = 'a';
let b = 'b';
let c = 'c';
let d = 'd';
let e = 'e';
let f = 'f';
let rest: string[];
let other: string;
[...(rest as (typeof b)[])] = ['x'];
for ((other as typeof c) of ['x']) {
}
(other as typeof d) = 'x';
[...(rest as { e: string }[])] = [{ e: 'x' }];
for ((other as `${typeof f}`) in {}) {
}
export const results = [s[0] === a, s[0] === b, s[0] === c, s[0] === d, s[0] === e, s[0] === f, rest, other];
