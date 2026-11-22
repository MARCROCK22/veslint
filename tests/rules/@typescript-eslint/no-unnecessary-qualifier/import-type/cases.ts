// The names after `import('…')` in a type are the qualifier of a TSImportType (an Identifier or a
// TSQualifiedName), no member access.
export namespace A {
  export const x = 1;
  export type T = typeof import('./cases').A.x;
  export type U = import('./cases').A.I;
  export interface I {}
  export type V = typeof A.x;
  export namespace B {
    export const y = 2;
    export type W = typeof import('./cases').A.B.y;
    export type X = typeof B.y;
  }
}
