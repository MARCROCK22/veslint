// ignoreBooleanCoercion: what is, through logical expressions, the branches of a conditional and
// the last expression of a sequence, an argument of a call to the built-in `Boolean`.
declare const a: string | undefined;
declare const b: string | undefined;
declare const c: string;
declare function use(...values: unknown[]): void;

use(Boolean(a || b));
use(Boolean(a || b || c));
use(Boolean((a || b) && c));
use(Boolean(c ? a || b : c));
use(Boolean(c ? c : a || b));
use(Boolean((c, a || b)));
use(Boolean(c, a || b));
use(Boolean?.(a || b));
use((Boolean)(a || b));
use(Boolean(c || (a ? a : b)));
let assigned: string | undefined;
use(Boolean((assigned ||= b)));

// Other shapes around the argument.
use(Boolean(a ? a : b));
use(Boolean((a || b, c)));
use(Boolean((a || b) as string));
use(Boolean(...[a || b]));
use(new Boolean(a || b));
use(String(a || b));
use(Boolean(() => a || b));
use(globalThis.Boolean(a || b));
use(Boolean(use(a || b)));

// Only a declaration of `Boolean` in the scope of the call itself counts.
function ownScope(Boolean: (x: unknown) => boolean) {
  use(Boolean(a || b));
  use([1].map(() => Boolean(a || b)));
}
function declaredLater() {
  use(Boolean(a || b));
  function Boolean(x: unknown) {
    return !!x;
  }
}
function outerScope() {
  const Boolean = (x: unknown) => !!x;
  return () => Boolean(a || b);
}
export { ownScope, declaredLater, outerScope };
