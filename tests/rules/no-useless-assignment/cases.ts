declare function read(n: number): void;
// Reported.
function overwritten(): number {
  let value = 1;
  value = 2;
  return value;
}
function unusedAfter(input: number): void {
  let total = input;
  read(total);
  total = total + 1;
}
function destructured(): void {
  let { a, b } = { a: 1, b: 2 };
  read(a);
  read(b);
  ({ a, b } = { a: 3, b: 4 });
}
function branches(flag: boolean): number {
  let result: number = 0;
  if (flag) {
    result = 1;
  } else {
    result = 2;
  }
  return result;
}
function counter(): void {
  let count = 0;
  read(count);
  count++;
}
// Not reported.
function used(flag: boolean): number {
  let value = 1;
  if (flag) {
    value = 2;
  }
  return value;
}
function loop(items: number[]): number {
  let sum = 0;
  for (const item of items) {
    sum += item;
  }
  return sum;
}
function inTry(): number {
  let state = 0;
  try {
    state = 1;
    read(state);
    state = 2;
  } catch {
    return state;
  }
  return 0;
}
function closure(): () => number {
  let captured = 1;
  const get = () => captured;
  captured = 2;
  return get;
}
let moduleValue = 1;
read(moduleValue);
moduleValue = 2;
export let exported = 1;
read(exported);
exported = 2;
export { overwritten, unusedAfter, destructured, branches, counter, used, loop, inTry, closure };
