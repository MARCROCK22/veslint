// Cases of no-unsafe-argument (typescript-eslint 8.62.0, no options), with strict.
declare const anyValue: any;
declare const list: any[];
declare const anyTuple: [number, any];
declare const tuplaRestAny: [number, ...any[]];
declare function numberValue(n: number): void;
declare function variadic(...n: number[]): void;
declare function tuple(...a: [number, string]): void;
declare function withUnknown(u: unknown): void;
declare function withSet(s: Set<string>): void;
declare function two(a: number, b: string): void;
declare function tagFn(parts: TemplateStringsArray, n: number): string;
declare class SomeClass { constructor(n: number) }

numberValue(anyValue);
withUnknown(anyValue);
variadic(1, anyValue);
variadic(...list);
variadic(...anyValue);
tuple(1, anyValue);
variadic(...anyTuple);
two(...tuplaRestAny);
withSet(new Set<any>());
anyValue(anyValue);
new SomeClass(anyValue);
tagFn`x${anyValue}`;
numberValue(missing);
two(1, anyValue as string);
two(1, ...[anyValue]);
numberValue(...[1]);

// Generic and synthesized signatures, optional calls, templates, parentheses, super and decorators.
declare function genericFn<T extends unknown[]>(...args: T): void;
declare const union: ((a: string, ...r: number[]) => void) | ((b: string) => void);
declare const optionalValue: ((n: number) => void) | undefined;
declare function withMap(m: Map<string, number>): void;
declare function tagFn2(parts: TemplateStringsArray, ...valueList: number[]): string;
declare function nested2(s: Set<Map<string, number>>): void;
declare function restTuple(...a: [number, ...string[]]): void;
genericFn(1, anyValue);
union('x', anyValue);
optionalValue?.(anyValue);
withMap(new Map());
tagFn2`a${1}b${anyValue}c${(anyValue)}`;
numberValue((anyValue));
nested2(new Set<Map<string, any>>());
restTuple(1, 'a', anyValue);
restTuple(...tuplaRestAny, anyValue);
class Base { constructor(n: number) { void n; } }
class Child extends Base { constructor() { super(anyValue); } }
function deco(n: number) { void n; return (..._: unknown[]) => {}; }
class WithDeco { @deco(anyValue) method() {} }
void import(anyValue);
void [Child, WithDeco];
