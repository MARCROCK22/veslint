// prefer-reduce-type-parameter: the fix removes the assertion and adds the type argument.
// Non-ASCII text before the ranges: ñ 😀 日本語.
declare const numbers: number[];

// `as`: the type goes after the callee.
numbers.reduce((acc, n) => [...acc, n], [] as number[]);
// Angle-bracket assertion.
numbers.reduce((acc, n) => [...acc, n], <number[]>[]);
// A parenthesized argument keeps its parentheses; parentheses around the expression go.
numbers.reduce((acc, n) => acc.concat(n), ([] as number[]));
numbers.reduce((acc, n) => acc.concat(n), ([]) as number[]);
numbers.reduce((acc, n) => acc.concat(n), <number[]>([]));
// A parenthesized type loses its parentheses in the type argument.
numbers.reduce((acc, n) => acc.concat(n), [] as (number[]));
// Existing type arguments: only the assertion is removed.
numbers.reduce<number[]>((acc, n) => [...acc, n], [] as number[]);
// Computed callee, optional chain and a parenthesized callee.
numbers['reduce']((acc, n) => acc + n, 0 as number);
numbers?.reduce((acc, n) => acc + n, 0 as number);
(numbers.reduce)((acc, n) => acc + n, 0 as number);
// Several lines and comments inside the ranges.
numbers.reduce(
  (acc, n) => ({ ...acc, [n]: String(n) }),
  {} /* empty */ as /* the type */ Record<
    number,
    string
  >,
);
// A trailing comma and a third argument.
numbers.reduce((acc, n) => acc + n, 0 as number, );
