// unicorn/no-array-reverse with allowExpressionStatement: false.
declare const list: number[];

list.reverse();
list?.reverse();
[...list].reverse();
