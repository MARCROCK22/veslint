// A configuration comment turns off the rules veslint does not have that the configuration turns
// on: no rule is left that veslint cannot judge a directive by, in this file.
/* eslint no-debugger: "off", no-console: 0 */
/* eslint not-a/plugin-rule: "error" */
declare const p: Promise<number>;
async function f() {
  // eslint-disable-next-line no-debugger
  p;
  // eslint-disable-next-line no-console, @typescript-eslint/no-floating-promises
  p;
  // eslint-disable-next-line
  void 0;
  // eslint-disable-next-line
  p;
  /* eslint-disable no-console, no-debugger */
  console.log(1);
  /* eslint-enable no-console */
}
export { f };
