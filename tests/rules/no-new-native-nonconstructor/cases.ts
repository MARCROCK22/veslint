// Reported.
const a = new (Symbol as any)('x');
const b = new (BigInt as any)(1);

// Not reported.
const c = Symbol('x');
const d = BigInt(1);
function shadow(Symbol: any) {
  return new Symbol();
}

// Reported (TypeScript reports them too).
// @ts-expect-error
const e = new Symbol('x');
// @ts-expect-error
const f = new BigInt(1);
