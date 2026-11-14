// unicorn/better-regex, removed in eslint-plugin-unicorn 79.0.0 ("Prefer `eslint-plugin-regexp`"): it
// reports nothing, not even what it used to shorten.
const r1 = /[0-9]/;
const r2 = /[^0-9]/u;
const r3 = /[a-zA-Z0-9_]/;
const r4 = new RegExp('[0-9]');
const r5 = /(?:a|b)/;

export {r1, r2, r3, r4, r5};
