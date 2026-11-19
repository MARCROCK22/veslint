/* eslint-disable no-console, eqeqeq */
const a = 1;
/* eslint-enable no-console */
const s = '😀'; /* eslint-disable no-var */
// Line directives close their own areas.
/* eslint-disable-next-line no-undef */
undefinedThing;
console.log(a, s); // eslint-disable-line no-console
/*
  eslint-disable no-debugger,
	curly -- the ids on other lines
*/
/* eslint-enable no-debugger */
/* eslint-disable no-empty */ /* eslint-enable no-empty */
/* eslint-disable prefer-const -- with a description */
/* eslint no-var: off */
function f(): number {
  /* eslint-disable */
  return a;
}
export { f };
