// unicorn/prefer-number-properties with checkNaN: `NaN` too, wherever it is read.
const a5 = NaN;
const a9 = { NaN };
const a10 = [NaN, -NaN, isNaN(NaN)];
let written = 0;
function f(value = NaN) {
  return value === NaN ? written : NaN;
}
