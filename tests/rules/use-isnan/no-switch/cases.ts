// use-isnan with enforceForSwitchCase false: only comparisons.
declare const x: number;

switch (NaN) {
  case NaN:
    break;
}
if (x === NaN) {}
