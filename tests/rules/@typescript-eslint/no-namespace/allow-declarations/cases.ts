// no-namespace with allowDeclarations: a declared namespace, or one inside a declared module or
// inside `declare global`, is allowed.
namespace A {}
module B {}
namespace C.D.E {}
export namespace F {
  export namespace G {}
}
declare namespace H {}
declare module I {}
export declare namespace J {
  namespace K {}
}
declare module 'string-named' {
  namespace L {}
}
declare global {
  namespace M {}
}
