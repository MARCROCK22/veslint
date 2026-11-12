// Reported: `module` before a name or a dotted name.
module Foo {}
module A.B.C {}
declare module Bar {}
export module Exported {}
export declare module ExportedDeclared {}
module /* comment */ Commented {}
declare module Outer {
  module Inner {}
  namespace Fine {}
  module Deep.Er {
    module Deepest {}
  }
}
namespace Holder {
  export module Nested {}
}
module module {}
module type {}

// Not reported.
namespace Good {}
declare namespace GoodDeclared {}
namespace A1.B1.C1 {}
declare module 'string-module' {}
declare module "double-quoted" {
  export const x: number;
}
declare global {
  interface Window {
    t3: string;
  }
}
declare module 'with-global' {
  global {
    interface Outside {
      x: number;
    }
  }
}
namespace module {}
namespace /* module */ Fooled {}
export {};
