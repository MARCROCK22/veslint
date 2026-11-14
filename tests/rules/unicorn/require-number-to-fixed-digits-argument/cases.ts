// unicorn/require-number-to-fixed-digits-argument: `toFixed()` is given its digits.
declare const n: number;
declare const box: { value: number };

const s1 = n.toFixed();
const s2 = box.value.toFixed( );
const s3 = (n as number).toFixed();
const s4 = n?.toFixed();

// Not reported.
const z1 = n.toFixed(2);
const z2 = n.toFixed?.();
const z3 = new Foo().toFixed();
const z4 = n['toFixed']();
class Foo {
  toFixed() {
    return '';
  }
}
