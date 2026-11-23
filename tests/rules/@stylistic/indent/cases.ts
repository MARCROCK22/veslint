// Default options: 4 spaces.
import {
    a,
  b,
        c as d,
} from './mod';
import def, * as ns from './mod';
import type {
    T1,
} from './mod';
export {
    a,
      b,
};
export * as all
    from './mod';
export {
    d as e,
}
from './mod';

declare function sink(...args: unknown[]): void;

function f(
    x: number,
  y: string,
        z?: boolean,
): number {
    if (x) {
        return 1;
    } else if (y) {
      return 2;
    }
    else
        return 3;
}

const arrow = (
    p: number,
    q: number,
) => p
    + q;

const obj = {
    one: 1,
  two: 2,
    three: {
        four: 4,
            five: 5,
    },
    method() {
        return this.one;
    },
    get value() {
      return 1;
    },
    [`computed`]:
        6,
};

const list = [
    1,
    2,
      3,
    [
        4,
    5,
    ],
];

const [
    first,
  second,
] = list;

const { one,
    two } = obj;

sink(
    1,
  2,
    () => {
        return 3;
    },
);

sink(1, 2,
    3, 4);

sink(function () {
    return 1;
}, function () {
  return 2;
});

const chain = list
    .map(x => x)
  .filter(Boolean)
    .reduce((acc, x) => acc
        + 1, 0);

const deep = obj.three
    .four;

const cond = first
    ? second
    : first;

const cond2 = first ?
    second :
  first;

const nested = first
    ? second
        ? 1
        : 2
    : 3;

switch (first) {
    case 1:
        sink();
        break;
  case 2:
    sink();
    break;
    case 3: {
        sink();
        break;
    }
    default:
        sink();
    // comment at the end of a switch
}

for (let i = 0;
    i < 10;
    i++) {
    sink(i);
}

for (const k in obj)
    sink(k);

for (const v of list)
  sink(v);

while (first)
    sink();

do
    sink();
while (first);

try {
    sink();
} catch (error) {
  sink(error);
} finally {
    sink();
}

label:
for (;;) {
    break label;
}

var v1 = 1,
    v2 = 2,
  v3 = 3;

let l1,
    l2;

const c1 = {
        bad: 1,
    },
    c2 = 2;

const assigned =
    1 + 2;

let target;
target =
    3;
target
    = 4;

const template = `line ${
    first
} more ${second}
    text ${
  first
}`;

const tagged = String.raw`
    ${first}
`;

class Base<T> {
    field = 1;
    other: number =
        2;
    static stat;
    private priv: string;
    #hash = 3;
    [key: string]: unknown;
    static {
        sink();
      sink();
    }
    constructor(
        public readonly a: number,
      private b: string,
    ) {
        super();
    }
    method(): void {
        sink();
    }
    get acc(): number {
        return 1;
    }
    accessor auto = 1;
}

class Derived
    extends Base<number>
    implements Iface {
    method(): void {}
}

abstract class Abstract {
    abstract prop: string;
    abstract method(): void;
  abstract other(
        x: number,
    ): void;
}

interface Iface
    extends Other, Third {
    a: number;
  b: string;
    c(
        x: number,
    ): void;
    new (x: number): Iface;
    (y: string): void;
    readonly [index: number]: string;
}

interface Other {}
interface Third {}

type Alias =
    | 'a'
    | 'b';

type Obj = {
    a: number;
      b: string;
    c: {
        d: number;
    };
};

type Mapped = {
    [K in keyof Obj]: Obj[K];
};

type Mapped2 = {
  readonly [K in keyof Obj]?: Obj[K];
};

type Cond<T> = T extends string
    ? 'string'
    : T extends number
    ? 'number'
    : 'other';

type Tuple = [
    number,
  string,
    ...boolean[],
];

type Fn = (
    a: number,
    b: string,
) => void;

type Indexed = Obj[
    'a'
];

type Generic<
    A,
  B = string,
> = A | B;

const instantiated = sink<
    number
>(1);

enum Color {
    Red,
  Green = 2,
    Blue =
        3,
}

namespace NS {
    export const x = 1;
  export const y = 2;
}

declare module 'mod' {
    export const z: number;
}

declare global {
    interface Window {
        x: number;
    }
}

function decorated(target: unknown) {
    return target;
}

@decorated
class WithDecorator {
    @decorated
    method() {}
    @decorated prop = 1;
}

const asExpr = first as
    unknown as
    string;

const satisfied = obj satisfies
    object;

const nonNull = obj!
    .one;

const logical = first &&
    second ||
        first;

const binary = 1 +
    2 *
  3;

(function () {
    sink();
})();

(() => {
    sink();
})();

const iife = (function () {
    return 1;
}());

const paren = (
    1 + 2
);

const parenMulti = (
    first
        ? 1
        : 2
);

async function asyncFn() {
    await sink(
        1,
    );
    const r = await import(
        './mod'
    );
    for await (const x of list) {
        sink(x);
    }
}

function* gen() {
    yield 1;
    yield* [
        2,
    ];
}

const optional = obj?.three
    ?.four;

const optCall = sink?.(
    1,
);

new Base(
    1,
);

new Base;

const meta = import.meta
    .url;

/*
 * A block comment
 */
  // misaligned comment
    // another one
sink();

    /* block comment indented */
sink();

if (first)
    sink()
;[1, 2].map(sink);

if (first) {
    sink();
}
// comment before else
else {
    sink();
}

export default {
    a: 1,
  b: 2,
};

export const exported = {
    a: 1,
};

export function exportedFn(
    a: number,
) {
    return a;
}

sink(`multi
line ${1} template`, {
    a: 1,
});

using res = { [Symbol.dispose]() {} };
