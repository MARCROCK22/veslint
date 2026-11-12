/** @deprecated Use `fresh` instead. */
export function stale(): void {}
export function fresh(): void {}
/** @deprecated */
export const oldValue = 1;
export const value = 2;
/** @deprecated Old class. */
export class OldClass {}
export class Ctor {
  /** @deprecated Do not construct without arguments. */
  constructor();
  constructor(x: number);
  constructor(x?: number) {
    void x;
  }
}
const local = 3;
export {
  /** @deprecated The alias is deprecated. */
  local as aliasedLocal,
};
export { local as plainAlias };
export default oldValue;
/** @deprecated The whole namespace. */
export namespace OldNs {
  export const inner = 1;
}
export interface Shape {
  /** @deprecated Use area2. */
  area(): number;
  area2(): number;
  /** @deprecated Property doc. */
  prop: string;
  fnProp: () => void;
  /** @deprecated Function property. */
  deprecatedFnProp: () => void;
}
