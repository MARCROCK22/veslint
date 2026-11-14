// unicorn/prefer-math-min-max: `Math.min()` and `Math.max()` instead of a ternary that compares
// two values and gives one of them.
declare let height: number;
declare const box: { value: number };

const m1 = height > 50 ? 50 : height;
const m2 = height < 50 ? height : 50;
const m3 = height >= 50 ? height : 50;
const m4 = height <= 50 ? 50 : height;
const m5 = box.value > 1 ? 1 : box.value;
const m6 = (height as number) > 2 ? 2 : height;
const m7 = height! > 2 ? 2 : height!;
function f(a: number, b = 1) {
  return a > b ? b : a;
}
function g() {
  return(height > 1 ? 1 : height);
}

// Not reported.
const z1 = height > 50 ? height : 49;
const z2 = height === 50 ? 50 : height;
const z3 = 1n > 2n ? 2n : 1n;
const z4 = new Date() > new Date() ? 1 : 2;
function h(a: string, b = 'x') {
  return a > b ? b : a;
}
function i(text = 'a') {
  const other = 'b';
  return text > other ? other : text;
}
const z5 = (height as unknown as string) > 'a' ? 'a' : height;
