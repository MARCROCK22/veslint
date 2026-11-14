// unicorn/prefer-string-trim-start-end: `trimStart()` and `trimEnd()` instead of their old names.
declare const text: string & { trimLeft(): string; trimRight(): string };

const s1 = text.trimLeft();
const s2 = text.trimRight();
const s3 = text?.trimLeft();
const s4 = (text as typeof text).trimRight();

// Not reported.
const z1 = text.trimLeft?.();
const z2 = text['trimLeft']();
const z3 = text.trimStart();
