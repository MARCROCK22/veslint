// no-unsafe-member-access: a qualified name is not a member access, whatever its length: in a
// type, in `import x = a.b.c` and in the name of a namespace. An import type is not one either.
import * as ns from './ns';
import deepAlias = ns.outer.inner.deep;
function qualified(
  a: ns.outer.inner.deep.Message,
  b: ns.outer.inner.Short,
  c: Array<ns.outer.inner.deep.Message>,
  d: import('./ns').outer.inner.deep.Message,
  e: import('./ns').Table['row'],
  f: typeof ns.outer.inner.deep.value,
  g: import('./ns').Table,
) {
  // Real member accesses on `any`, which are reported.
  ns.outer.inner.deep.value.x;
  deepAlias.value.y;
  g.loose.z;
  return [a, b, c, d, e, f];
}
namespace first.second.third {
  export const z = 1;
}
export { qualified, first };
