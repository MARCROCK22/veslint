// Reported: string literals of more than one grapheme.
export const a1 = /[\q{abc}]/v;
export const a2 = /[\q{a|bc|def}]/v;
export const a3 = /[\q{🇦🇨🇦🇩}]/v;
export const a4 = new RegExp('[\\q{é|xy}]', 'v');
// Not reported.
export const b1 = /[\q{a}]/v;
export const b2 = /[\q{🇦🇨}]/v;
export const b3 = /[\q{é}]/v;
export const b4 = /[\q{👨‍👩‍👧}]/v;
