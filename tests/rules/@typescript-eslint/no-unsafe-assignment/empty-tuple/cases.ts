// Empty array literals whose type is the empty tuple: tsgo 7.0.2 panicked on them; 7.1.0-beta
// answers, and tests/run.sh checks that every node is analyzed.
declare const anyValue: any;
declare function takes(a: []): void;
const constTuple = [] as const;
const annotated: [] = [];
const asserted = [] as [];
function returned(): [] {
  return [];
}
takes([]);
const unsafe: string = anyValue;
const plain: number[] = [];
const alsoUnsafe: number = anyValue;
export { constTuple, annotated, asserted, returned, unsafe, plain, alsoUnsafe };
