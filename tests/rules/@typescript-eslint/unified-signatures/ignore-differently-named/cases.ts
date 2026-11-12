declare function f(a: string): void;
declare function f(b: number): void;
declare function g(a: string): void;
declare function g(a: number): void;
declare function h(...a: string[]): void;
declare function h(...b: number[]): void;
declare function i({ a }: { a: string }): void;
declare function i({ b }: { b: number }): void;
declare function j(a: string): void;
declare function j(...a: number[]): void;
declare function k(a: string): void;
declare function k(b: string, c?: number): void;
declare function l(a: string): void;
declare function l(a: string, c?: number): void;
declare function m(this: Foo, a: string): void;
declare function m(this: Foo, a: number): void;
declare class Foo {
  constructor(a: string);
  constructor(b: number);
}
export {};
