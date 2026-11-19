// Reported (staticProperties: $1 and input; no prototype method).
export const a1 = RegExp.$1;
export const a2 = RegExp.input;
// Not reported.
export const b1 = RegExp.$2;
/a/.compile('b');
