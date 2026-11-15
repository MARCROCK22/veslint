type Fn = (a: number) => number;
export const typedVar: Fn = (a) => a;
export const asserted = ((a) => a) as Fn;
export const constAssert = () => ({ a: 1 }) as const;
export const higher = (): Fn => (a) => a;
export function higherDecl() {
  return (a: number): number => a;
}
export const o: { f: Fn } = { f: (a) => a };
