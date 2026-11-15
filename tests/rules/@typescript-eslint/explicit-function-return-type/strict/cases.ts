// Reported: everything without a return type.
type Fn = () => number;
const typedVar: Fn = () => 1;
const asserted = (() => 1) as Fn;
const higher = () => () => 1;
const constAssert = () => ({ a: 1 }) as const;
function returnsTyped(): Fn {
  return () => 1;
}
class C {
  p: Fn = () => 1;
}
foo(() => 1);
declare function foo(f: unknown): void;
// Not reported.
const typed = (): number => 1;
function decl(): void {}
