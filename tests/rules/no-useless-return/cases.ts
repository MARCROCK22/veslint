declare function work(): void;
// Reported.
function last(): void {
  work();
  return;
}
function inBranches(flag: boolean): void {
  if (flag) {
    work();
    return;
  } else {
    return;
  }
}
const arrow = (): void => {
  work();
  return;
};
class Service {
  run(): void {
    try {
      work();
    } catch {
      return;
    }
  }
}
function inSwitch(n: number): void {
  switch (n) {
    case 1:
      work();
      return;
  }
}
function withComment(): void {
  work();
  return /* why */;
}
// Not reported.
function value(): number {
  return 1;
}
function early(flag: boolean): void {
  if (flag) {
    return;
  }
  work();
}
function inLoop(items: number[]): void {
  for (const item of items) {
    if (item) {
      return;
    }
  }
}
function inFinally(): void {
  try {
    work();
  } finally {
    return;
  }
}
export { last, inBranches, arrow, Service, inSwitch, withComment, value, early, inLoop, inFinally };
