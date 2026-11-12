// With rules veslint does not have (no-debugger and no-console are on here). A directive that
// names one of them is not judged by veslint, so here each one suppresses a real problem.
declare const p: Promise<number>;
async function f() {
  // eslint-disable-next-line no-debugger
  debugger;
  // eslint-disable-next-line no-console, @typescript-eslint/no-floating-promises
  console.log(1), p;
  // eslint-disable-next-line @typescript-eslint/await-thenable, no-alert
  p;
  // eslint-disable-next-line not-a/plugin-rule
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  p;
}
export { f };
