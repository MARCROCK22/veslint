// prefer-find: `.filter(…)[0]` and `.filter(…).at(0)` on arrays.
declare const numbers: number[];
declare const maybe: number[] | undefined;
declare const nullable: string[] | null;
declare const tuple: [number, string];
declare const union: number[] | string[];
declare const both: number[] & string[];
declare const mixed: number[] | Set<number>;
declare const notArray: { filter(f: (x: number) => boolean): number[] };
declare const anything: any;
declare function isEven(n: number): boolean;

// Reported: member access of zero.
numbers.filter(isEven)[0];
numbers.filter(isEven)['0'];
numbers.filter(isEven)[`0`];
numbers.filter(isEven)[-0];
numbers.filter(isEven)[0.0];
numbers['filter'](isEven)[0];
numbers[`filter`](isEven)[0];
(numbers.filter(isEven))[0];
maybe?.filter(isEven)[0];
nullable!.filter((s) => s.length > 0)[0];
tuple.filter((x) => x)[0];
union.filter((x: number | string) => x)[0];
both.filter((x) => x)[0];
(Math.random() > 0.5 ? numbers.filter(isEven) : numbers.filter((n) => n > 1))[0];
(isEven(1), numbers.filter(isEven))[0];
/* 😀 */ numbers.filter(isEven)[0];

// Reported: `.at()` with an argument Array#at treats as 0.
numbers.filter(isEven).at(0);
numbers.filter(isEven).at(-0);
numbers.filter(isEven).at(0.5);
numbers.filter(isEven).at(-0.9);
numbers.filter(isEven).at('0');
numbers.filter(isEven).at('abc' as unknown as number);
numbers.filter(isEven).at(NaN as number);
numbers.filter(isEven).at(0n as unknown as number);
numbers.filter(isEven).at(null as unknown as number);
numbers.filter(isEven).at([] as unknown as number);
numbers.filter(isEven).at(undefined as unknown as number);
numbers.filter(isEven)['at'](0);
numbers.filter(isEven).at?.(0);

// Reported: the index is a constant (resolved with the scope).
const zero = 0;
let zeroText = '0';
numbers.filter(isEven)[zero];
numbers.filter(isEven)[zeroText];
numbers.filter(isEven).at(zero);

// Not reported.
let index = 0;
index = 1;
numbers.filter(isEven)[index];
numbers.filter(isEven)[1];
numbers.filter(isEven)['00'];
numbers.filter(isEven)?.[0];
numbers.filter(isEven)?.at(0);
numbers.filter?.(isEven)[0];
numbers.filter(isEven).at(1);
numbers.filter(isEven).at(-1);
numbers.filter(isEven).at();
numbers.filter(isEven).at(0, 1);
numbers.filter(isEven).at(...[0]);
numbers.filter(isEven)[0 + 1];
numbers.find(isEven);
numbers.map(isEven)[0];
mixed.filter?.(isEven)[0];
notArray.filter(isEven)[0];
anything.filter(isEven)[0];
(Math.random() > 0.5 ? numbers.filter(isEven) : numbers)[0];
(Math.random() > 0.5 ? numbers.filter(isEven) : notArray.filter(isEven))[0];
// A static index through a Set, a Map and Object.keys.
numbers.filter(isEven)[new Set().size];
numbers.filter(isEven)[new Map([['i', 0]]).get('i')!];
numbers.filter(isEven).at(Object.keys('').length);
numbers.filter(isEven)[new Set([1]).size];
