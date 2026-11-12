interface Box {
  value: number;
}

type A = string | string;
type B = Box & Box;
type C = (Box & Box) | (string | string);
function optional(a?: string | undefined): void {}

export type { A, B, C };
export { optional };
