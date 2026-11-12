// Lines end with CRLF.
declare function f(a: string): void;
declare function f(a: number): void;

declare function f(a: boolean): void;
declare function g(): void;
declare function g(
  a: string,
): void;
declare function g(a: string, b?: number): void;
export {};
