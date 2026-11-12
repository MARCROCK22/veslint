// no-namespace with allowDeclarations and without allowDefinitionFiles (this is no definition
// file): the same as allowDeclarations.
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
