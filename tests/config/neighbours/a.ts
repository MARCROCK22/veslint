// Directive comments around the rules veslint does not have. Here no-debugger and no-console are
// on, and no-alert and @typescript-eslint/await-thenable are off.
declare const p: Promise<number>;
async function f() {
  // A rule veslint has and one it does not have, which suppresses a problem: the first is unused.
  // eslint-disable-next-line no-console, @typescript-eslint/no-floating-promises
  console.log(1);
  /* eslint-disable no-debugger, @typescript-eslint/no-floating-promises */
  debugger;
  /* eslint-enable no-debugger, @typescript-eslint/no-floating-promises */
  // Both suppress something.
  // eslint-disable-next-line no-debugger, @typescript-eslint/no-floating-promises
  debugger; p;
  // An eslint-enable is used when a directive before it disables its rule, whatever the rule
  // finds: also for a rule veslint does not have.
  /* eslint-enable no-console */
  /* eslint-disable no-console */
  console.log(2);
  /* eslint-enable no-console */
  /* eslint-enable no-debugger, @typescript-eslint/no-floating-promises */
  // A rule that is off in the configuration finds nothing, so a directive for it is unused: one
  // of veslint's rules, and one it does not have.
  // eslint-disable-next-line @typescript-eslint/await-thenable
  await 1;
  // eslint-disable-next-line no-alert
  alert(1);
  // eslint-disable-next-line no-alert, @typescript-eslint/no-floating-promises
  p;
  /* eslint-disable no-alert */
  alert(2);
  /* eslint-enable no-alert */
  // A rule of a plugin the configuration does not have.
  // eslint-disable-next-line not-a/plugin-rule, @typescript-eslint/no-floating-promises
  p;
  /* eslint-enable not-a/plugin-rule */
}
export { f };
