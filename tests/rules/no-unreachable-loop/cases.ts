declare function work(n: number): boolean;
// Reported.
function once(items: number[]): void {
  for (const item of items) {
    work(item);
    break;
  }
  while (work(0)) {
    return;
  }
  do {
    throw new Error('x');
  } while (work(1));
  for (let i = 0; i < 10; i++) {
    if (work(i)) {
      break;
    } else {
      return;
    }
  }
  for (const key in { a: 1 }) {
    console.log(key);
    break;
  }
}
// Not reported.
function loops(items: number[]): number | undefined {
  for (const item of items) {
    if (work(item)) {
      return item;
    }
  }
  while (work(2)) {
    if (work(3)) {
      continue;
    }
    break;
  }
  outer: for (const a of items) {
    for (const b of items) {
      if (a === b) {
        continue outer;
      }
    }
    break;
  }
  return undefined;
}
export { once, loops };
