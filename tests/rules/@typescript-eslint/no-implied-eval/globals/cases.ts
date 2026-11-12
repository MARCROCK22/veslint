// `/* global */` comments and lib names give ESLint variables without definitions: a reference
// to them is still a reference to the global.
/* global setTimeout, execScript:writable */
/* global setInterval:off */
setTimeout('alert(1)', 100);
setInterval('alert(1)', 100);
window.setTimeout('alert(1)', 100);
globalThis.setInterval('alert(1)', 100);
function shadowed(setImmediate: (code: string) => void) {
  setImmediate('alert(1)');
}
const fn = new Function('a', 'return a');
export { shadowed, fn };
