// The names after `import('…')` in a type are the qualifier of a TSImportType (an Identifier or a
// TSQualifiedName), no member access: no-iterator reports none of them, only the member accesses.
export const __iterator__ = {};
export type A = typeof import('./cases').__iterator__;
export type B = typeof import('./cases').__iterator__.constructor;
export type C = import('./cases').__iterator__;
declare const o: { __iterator__: object };
export const e = o.__iterator__;
export type F = typeof o.__iterator__;
export type G = typeof o['__iterator__'];
