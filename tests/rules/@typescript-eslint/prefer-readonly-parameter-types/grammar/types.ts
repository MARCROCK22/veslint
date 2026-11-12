export interface Mutable {
  a: number;
}
export interface Frozen {
  readonly a: number;
}
export interface Table {
  row: number[];
  readonly frozen: readonly number[];
}
export const mutableValue: Mutable = { a: 1 };
export const frozenValue: Frozen = { a: 1 };
export interface Holder<T = string> {
  value: T;
}
