declare function work(): void;
// Reported.
function afterReturn(): number {
  return 1;
  work();
  work();
}
function afterThrow(): never {
  throw new Error('x');
  const unused: number = 1;
}
function afterLoop(): void {
  while (true) {
    work();
  }
  work();
}
function afterBreak(items: number[]): void {
  for (const item of items) {
    break;
    console.log(item);
  }
}
function bothBranches(flag: boolean): number {
  if (flag) {
    return 1;
  } else {
    return 2;
  }
  let late = 3;
}
class Base {}
class Derived extends Base {
  field = 1;
  constructor() {
    return;
  }
}
// Not reported.
function hoisted(): number {
  return helper();
  function helper(): number {
    return 1;
  }
  var declaredOnly;
}
function fine(flag: boolean): number {
  if (flag) {
    return 1;
  }
  return 2;
}
function typeAfter(): number {
  return 1;
  type Later = string;
  interface AlsoLater {}
}
export { afterReturn, afterThrow, afterLoop, afterBreak, bothBranches, Derived, hoisted, fine, typeAfter };
