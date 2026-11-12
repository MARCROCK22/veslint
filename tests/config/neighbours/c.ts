// A configuration comment turns on a rule veslint does not have: a directive that names it
// suppresses its problem.
/* eslint no-alert: "error" */
declare const p: Promise<number>;
async function f() {
  // eslint-disable-next-line no-alert
  alert(1);
  // eslint-disable-next-line no-alert, @typescript-eslint/no-floating-promises
  alert(2), p;
  // eslint-disable-next-line no-alert, @typescript-eslint/no-floating-promises
  alert(3);
}
export { f };
