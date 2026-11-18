const value = { a: 1 };
let n = 0;
export const r1 = value ? 1 : 2;
export const r2 = value?.a;
export const r3 = n ?? 3;
export const r4 = [1, 2].find(() => 'x');
while (true) {
  n++;
  if (n > 10) {
    break;
  }
}
for (; value; ) {
  break;
}
do {
  n--;
} while (n);
