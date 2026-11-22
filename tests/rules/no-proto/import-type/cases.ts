// The names after `import('…')` in a type are the qualifier of a TSImportType (an Identifier or a
// TSQualifiedName), no member access: no-proto reports none of them, only the member accesses.
export const __proto__ = {};
export type A = typeof import('./cases').__proto__;
export type B = typeof import('./cases').__proto__.constructor;
export type C = import('./cases').__proto__;
export type D = typeof import('./cases').__proto__<number>;
declare const o: { __proto__: object };
export const e = o.__proto__;
export type F = typeof o.__proto__;
export type G = typeof o['__proto__'];
export type H = (typeof o)['__proto__'];
declare const p: { __proto__: <T>() => T };
export type I = typeof p.__proto__<number>;
export const j = p.__proto__<number>;
