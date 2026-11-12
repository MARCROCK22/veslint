// no-namespace with its default options: every `namespace` and `module` with a name (declared ones
// too, starting at `declare`), not `declare global` nor a module named by a string.
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
