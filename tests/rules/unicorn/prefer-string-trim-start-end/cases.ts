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

// 79.0.0: receivers known not to be strings are left.
declare const custom: { trimLeft(): string };
declare const bytes: Uint8Array & { trimLeft(): Uint8Array };
declare const anything: any;
custom.trimLeft();
bytes.trimLeft();
anything.trimRight();
[1].trimLeft?.();
declare const holder: { text: string; bytes: Uint8Array & { trimLeft(): Uint8Array }; literal: 'a' | 'b' };
holder.text.trimLeft();
holder.bytes.trimLeft();
holder.literal.trimRight();
