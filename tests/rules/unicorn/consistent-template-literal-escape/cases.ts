// unicorn/consistent-template-literal-escape: `${` is escaped as `\${` in a template literal.
declare const name: string;
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;

const t1 = `$\{a}`;
const t2 = `\$\{a}`;
const t3 = `${name} $\{b} and $\{c}`;
const t4 = `\\$\{a}`;

// Not reported.
const z1 = `\${a}`;
const z2 = `\\\$\{a}`;
const z3 = tag`$\{a}`;
const z4 = String.raw`$\{a}`;
