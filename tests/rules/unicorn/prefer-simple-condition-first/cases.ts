// unicorn/prefer-simple-condition-first: in a condition, a simple test (a name, its negation, or
// `===`/`!==` of a name with a name or a literal) goes before a conditional expression.
declare let a: boolean, b: boolean, c: boolean, d: number, e: string;
declare function f(): boolean;

if ((a ? b : c) && d === 1) {}
if ((a ? b : c) || !e) {}
while ((a ? b : c) && e !== 'x') {}
do {} while ((a ? b : c) || d === -1);
for (; (a ? b : c) && !!a;) {}
const x1 = ((a ? b : c) && (a || b)) ? 1 : 2;
const x2 = !((a ? b : c) && a);
if (((a ? b : c)) && (a)) {}
if ((a ? b : c) && a === b) {}
if ((a ? b : c) && a && b) {}
// TypeScript: assertions in the conditional.
if (((a as boolean) ? b! : <boolean>c) && a) {}
// A comment between: reported without the fix.
if ((a ? b : c) /* why */ && a) {}

// Not reported.
if (a && (a ? b : c)) {}
if ((a ? f() : c) && a) {}
if ((a ? new Boolean(b) : c) && a) {}
if ((a ? e.length > 0 : c) && a) {}
if ((a ? 'k' in {} : c) && a) {}
if ((a ? (b = c) : c) && a) {}
if (f() && a) {}
const z1 = (a ? b : c) && a;
if ((a ? b : c) && d === e.length) {}
if ((a ? b : c) && 1 === 2) {}
if ((a ? b : c) ?? a) {}
