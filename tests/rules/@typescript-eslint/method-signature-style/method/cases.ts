interface I1 {
  a: () => void;
  b: <T>(x: T, y?: string) => T,
  c?: (this: I1, ...rest: number[]) => number;
  readonly d: () => void;
  ['e']: (a: string) => string;
  f: (() => void);
  g: () => void | (() => void);
  h(): void;
  i: string;
  j: new () => object;
  'k-l': (  a: string  ,  ) => void
}
type T1 = {
  a: () => void;
  readonly b: (x: number) => this;
};
declare namespace NS {
  interface I2 {
    m: () => void;
  }
}
export type { I1, T1, NS };
