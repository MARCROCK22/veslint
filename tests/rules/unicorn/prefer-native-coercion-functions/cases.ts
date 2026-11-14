// unicorn/prefer-native-coercion-functions: `String`, `Number`, `BigInt`, `Boolean` and `Symbol`
// directly instead of a function that only calls one of them, and `Boolean` instead of an identity
// callback of `filter` and the like.
declare const list: unknown[];

const f1 = (v: unknown) => String(v);
const f2 = (v: unknown) => {
  return Number(v);
};
const f3 = function (v: unknown) {
  return Boolean(v);
};
function f4(v: unknown) {
  return BigInt(v as number);
}
const f5 = list.filter((v) => v);
const f6 = list.some(function (v) {
  return v;
});
const o1 = {
  method(v: unknown) {
    return String(v);
  },
};
class K {
  method(v: unknown) {
    return Symbol(v as string);
  }
}
const f7 = (v: unknown, w: unknown) => String(v);
const f8 = (v: unknown) => String(v /* why */);

// Not reported.
const z1 = (v: unknown) => String(v, 1 as never);
const z2 = async (v: unknown) => String(v);
const z3 = (v: unknown) => String(v.toString());
const z4 = list.map((v) => v);
const z5 = list.filter((v): v is string => v as boolean);
const z6 = ({ v }: { v: unknown }) => String(v);
class L {
  set value(v: string) {
    String(v);
  }
}
const z7 = ((v: unknown) => v)(1);
