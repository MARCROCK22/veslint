interface I1 {
  m(): void;
  n<T>(a: T, b?: string): T,
  o(this: I1, ...rest: number[]);
  p?(a: string): number;
  ['q'](): string;
  [Symbol.iterator](): Iterator<number>;
  r(): this;
  s(): Promise<this | null>;
  get t(): number;
  set t(v: number);
  u: () => void;
  'v-w'(  a: string  ,  ): void
}
type T1 = {
  m(): void;
  n(a: number): string;
  n(a: string): number;
  n(a: boolean): this;
};
interface I2 {
  f(a: string): void;
  g(): void;
  f(a: number): void;
}
declare namespace NS {
  interface I3 {
    m(): void;
    m(a: number): void;
  }
}
declare module 'mod' {
  interface I4 {
    m(): void;
  }
}
declare global {
  interface I5 {
    gm(): void;
  }
}
type T2 = { a(): void };
type T3 = { b(): void; b(x: string): void }
export type { I1, T1, I2, NS, T2, T3 };
