// Reported (TypeScript reports most of them too).
// @ts-expect-error
Object = null;
// @ts-expect-error
undefined = 1;
// @ts-expect-error
Math++;

// Not reported.
let local = 0;
local = 1;
function shadow(Object: any) {
  Object = null;
}
