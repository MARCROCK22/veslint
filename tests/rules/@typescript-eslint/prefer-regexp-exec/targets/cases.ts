// A regular expression in a variable is only known while nothing writes the variable after its
// initializer. In the target of a destructuring assignment or of a for-of loop, typescript-eslint's
// scope manager writes every identifier it finds, also those inside the type of an assertion, so
// `typeof b` there makes `b` unknown and the rule cannot tell that it has no `g` flag. Around a
// plain assignment target the type is only read.
declare const s: string;
let a = /a/;
let b = /b/;
let c = /c/;
let d = /d/;
let e = /e/;
let list: RegExp[];
let one: RegExp;
[...(list as (typeof b)[])] = [/x/];
for ((one as typeof c) of [/x/]) {
}
(one as typeof d) = /x/;
[...(list as [e: RegExp])] = [/x/];
export const results = [s.match(a), s.match(b), s.match(c), s.match(d), s.match(e), list, one];
