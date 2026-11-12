// `export =` of a namespace.
namespace Lib {
  export const v = 1;
  export const w = Lib.v;
}
export = Lib;
