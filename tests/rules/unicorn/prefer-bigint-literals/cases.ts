// unicorn/prefer-bigint-literals: a bigint literal instead of `BigInt(…)` of a literal.
declare const n: number;

const b1 = BigInt(1);
const b2 = BigInt('42');
const b3 = BigInt(-1);
const b4 = BigInt(- -1);
const b5 = BigInt(+1);
const b6 = BigInt('+1');
const b7 = BigInt(' 7 ');
const b8 = BigInt('-0');
const b9 = BigInt('0x1F');
const b10 = BigInt(0x1f);
const b11 = BigInt(0b1010);
const b12 = BigInt(1_000);
const b13 = BigInt(1e3);
const b14 = BigInt(9007199254740993);
const b15 = BigInt(123456789012345678901234567890);
const b16 = BigInt(/* one */ 1);
const b17 = BigInt('');
const b18 = (BigInt(-2));
let y = 1
BigInt(-3).toString()

// Not reported.
const z1 = BigInt(n);
const z2 = BigInt(1.5);
const z3 = BigInt('1.5');
const z4 = BigInt('abc');
const z5 = BigInt?.(1);
const z6 = BigInt(1, 2);
const z7 = BigInt(1n);
const z8 = BigInt(~1);
