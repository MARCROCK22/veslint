declare function work(n: number): boolean;
// Reported: a for-of.
function once(items: number[]): void {
  for (const item of items) {
    work(item);
    break;
  }
}
// Not reported: while and for-in are ignored.
function ignored(): void {
  while (work(0)) {
    return;
  }
  for (const key in { a: 1 }) {
    console.log(key);
    break;
  }
}
export { once, ignored };
