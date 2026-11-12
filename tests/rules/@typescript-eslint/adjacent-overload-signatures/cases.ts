// adjacent-overload-signatures: the overloads of a function, method or signature must follow each
// other in the program, a block, a module, a class, an interface or a type literal. Reported at the
// member that comes back after something else (with its export, `declare` or decorators).
declare function dec(...args: unknown[]): any;

export function a(x: string): void;
export function a(x: number): void;
export function b(): void {}
export function a(x: unknown) {}
declare function c(): void;
declare function d(): void;
declare function c(x: string): void;
export declare function e(): void;
type Between = number;
export declare function e(x: string): void;
function f(): void {}
const g = 1;
function f(x?: string): void {}
function* h() {}
async function i() {}
function* h() {}
export default function j(x: string): void;
export function k(): void;
export default function j(x: unknown) {}
export { a as aa };

function wrapper() {
  function inner(x: string): void;
  function inner(x: number): void;
  let between = 1;
  function inner(x: unknown) {}
  if (between) {
    function block(): void {}
    between++;
    function block(): void {}
  }
  const arrow = () => {
    function other(): void {}
    void 0;
    function other(): void {}
  };
  try {
    function t(): void {}
    ;
    function t(): void {}
  } catch {
    function t(): void {}
  }
}

declare module 'mod' {
  export function m(): void;
  function n(): void;
  export function m(x: string): void;
}
declare global {
  function glob(): void;
  var between: number;
  function glob(x: string): void;
}
namespace Space {
  export function s(): void {}
  export const between = 1;
  export function s(): void {}
}

class Klass {
  constructor(x: string);
  name = '';
  constructor(x?: string) {}
  method(): void;
  static method(): void;
  method(x?: string): void {}
  static method(x?: string): void {}
  get acc(): number {
    return 1;
  }
  other() {}
  set acc(value: number) {}
  #priv(): void;
  '#priv'(): void;
  #priv(x?: number): void {}
  '#priv'(x?: number): void {}
  'quoted'(): void;
  quoted(x?: string): void {}
  ['computed'](): void {}
  between = 1;
  computed(): void {}
  [Symbol.iterator](): void {}
  between2 = 1;
  [Symbol.iterator](): void {}
  [`template`](): void {}
  between3 = 1;
  [`template`](): void {}
  1(): void {}
  between4 = 1;
  '1'(): void {}
  [1](): void {}
  1n(): void {}
  between5 = 1;
  [undefined](): void {}
  undefined(): void {}
  @dec decorated(): void {}
  between6 = 1;
  @dec
  // a comment between
  decorated(): void {}
  static {
    function inStaticBlock(): void {}
    void 0;
    function inStaticBlock(): void {}
  }
}

abstract class Abstract {
  foo(): void;
  abstract bar(): void;
  foo(x?: string): void {}
  abstract baz(): void;
  qux(): void {}
  abstract baz(x: string): void;
}

interface Iface {
  (x: string): void;
  call(): void;
  (x: number): void;
  new (x: string): Iface;
  new(): void;
  new (x: number): Iface;
  method(): void;
  prop: string;
  method(x: string): void;
  get g(): string;
  set g(value: string);
  other(): void;
  get g(): string;
  [key: string]: unknown;
}

type Literal = {
  foo(): void;
  bar: string;
  foo(x: string): void;
  nested: {
    baz(): void;
    qux(): void;
    baz(x: string): void;
  };
};

const object = {
  foo() {},
  bar() {},
  foo2() {},
};

const Expression = class {
  foo(): void {}
  bar(): void {}
  foo(x?: string): void {}
};
