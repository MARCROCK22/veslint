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

// 79.0.0: chains are reordered at once; `typeof`, nullish and static string comparisons are simple;
// an operand that is not safe to move before a simple one only gets the "unsafe" report; comments
// and TypeScript wrappers keep the fix away.
declare let u: unknown, s: string | null;
if (f() && a && b) {}
if (f() || typeof u === 'string') {}
if (f() && s != null) {}
if (f() && d === -1) {}
if (f() && e === `x`) {}
if (f() && (a ? b : c) && b) {}
if ((a ? f() : c) && b) {}
if (f() /* keep */ && a) {}
if ((f() as boolean) && a) {}
if (typeof u !== 'undefined' && f() && u) {}
const r1 = Boolean(f() && a);
const r2 = !(f() || a);
const r3 = (f() && a) as boolean;
while (f() && a) {}
// Safe to move: a conditional of simple parts.
if ((a ? b : c) && d === 1) {}
if ((a ? b : c) || !a || (b ? 1 : 2)) {}
if ((a ? b : c) /* keep */ && a) {}
const r4 = Boolean((a ? b : c) && a);
