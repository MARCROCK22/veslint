// `lib` of the parser options replaces the libs of the tsconfig for the scope manager: with the
// lib of ES5, `WeakMap` is only ESLint's global.
export const a = class WeakMap {};
export const b = class Object {};
