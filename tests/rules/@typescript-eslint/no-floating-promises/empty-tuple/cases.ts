// tsgo 7.0.2 panicked listing the members of a union with an empty tuple (TypeScript#63869);
// 7.1.0-beta answers, and tests/run.sh checks that every node is analyzed.
declare const pair: [string] | null;
declare const p: Promise<number>;
async function f() {
  pair || [];
  p;
  (pair ?? []).length;
}
export { f };
