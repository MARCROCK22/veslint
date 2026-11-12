// prefer-for-of: `for (let i = 0; i < arr.length; i++)` whose body only reads `arr[i]`.
declare const arr: number[];
declare const arr2: number[];
declare const obj: { arr: number[]; [key: string]: unknown };
declare function doMath(n: number): void;

for (let i = 0; i < arr.length; i++) {
  doMath(arr[i]);
}
for (var i1 = 0; i1 < arr.length; ++i1) doMath(arr[i1]);
for (let i2 = 0; i2 < arr.length; i2 += 1) {}
for (let i3 = 0; i3 < arr.length; i3 = i3 + 1) {}
for (let i4 = 0; i4 < arr.length; i4 = 1 + i4) {}
for (let i5 = 0.0; i5 < arr.length; i5 += 1.0) {}
for (let i6 = 0x0; i6 < arr.length; i6 += 0x1) {}
for (let i7 = (0); (i7 < arr.length); (i7++)) {}
for (let i8 = 0; (i8) < (arr).length; i8 = (i8 + 1)) {
  doMath((arr)[(i8)]);
}
for (let i9 = 0; i9 < obj.arr.length; i9++) {
  doMath(obj.arr[i9]);
}
for (let i10: number = 0; i10 < arr.length; i10++) {
  doMath(arr[i10]!);
  doMath(arr?.[i10]);
  setTimeout(() => doMath(arr[i10]));
}
for (let i11 = 0; i11 < arr.length; i11++) {
  for (let i11 = 0; i11 < arr.length; i11++) {}
}
for (let i12 = 0; i12 < arr.length; i12++) {
  obj[arr[i12]] = 1;
  delete obj[arr[i12]];
  [obj[arr[i12]]] = [1];
  ({ key: obj[arr[i12]] } = { key: 1 });
}
for (let i13 = 0; i13 < arr.length; i13++) {
  // An object pattern is not an ObjectExpression: isAssignee does not see it.
  ({ key: arr[i13] } = { key: 1 });
}
for (let i14 = 0; i14 < arr[length]; i14++) {}
for (let i15 = 0; i15 < arr.length; i15++) {
  arr[i15].toFixed();
}

// Not the shape of the loop.
for (const c1 = 0; c1 < arr.length; c1++) {}
for (let c2 = 0, c3 = 1; c2 < arr.length; c2++) {}
for (let c4 = 1; c4 < arr.length; c4++) {}
for (let c5 = 0n; c5 < arr.length; c5++) {}
for (let c6 = -0; c6 < arr.length; c6++) {}
for (let c7 = '0'; c7 < arr.length; c7++) {}
for (let [c8] = [0]; c8 < arr.length; c8++) {}
for (let c9 = 0; c9 <= arr.length; c9++) {}
for (let c10 = 0; arr.length > c10; c10++) {}
for (let c11 = 0; c11 < arr?.length; c11++) {}
for (let c12 = 0; c12 < arr.length!; c12++) {}
for (let c13 = 0; c13 < arr['length']; c13++) {}
for (let c14 = 0; c14 < arr.size; c14++) {}
for (let c15 = 0; c15 < arr.length; c15--) {}
for (let c16 = 0; c16 < arr.length; c16 += 2) {}
for (let c17 = 0; c17 < arr.length; c17 = c17 + 2) {}
for (let c18 = 0; c18 < arr.length; c18 = c18 - 1) {}
for (let c19 = 0; c19 < arr.length; c19++, doMath(0)) {}
for (let c20 = 0; c20 < arr.length; ) {}
for (let c21 = 0; ; c21++) {}
let c22 = 0;
for (c22 = 0; c22 < arr.length; c22++) {}
for (; c22 < arr.length; c22++) {}
for (const c23 in obj) {
  doMath(Number(c23));
}
for (const c24 of arr) {
  doMath(c24);
}

// The index is used otherwise in the body.
for (let u1 = 0; u1 < arr.length; u1++) {
  doMath(u1);
}
for (let u2 = 0; u2 < arr.length; u2++) {
  doMath(arr[u2 + 1]);
}
for (let u3 = 0; u3 < arr.length; u3++) {
  arr[u3] = 0;
}
for (let u4 = 0; u4 < arr.length; u4++) {
  arr[u4]++;
}
for (let u5 = 0; u5 < arr.length; u5++) {
  delete arr[u5];
}
for (let u6 = 0; u6 < arr.length; u6++) {
  [arr[u6]] = [1];
}
for (let u7 = 0; u7 < arr.length; u7++) {
  [...arr[u7]] = [1];
}
for (let u8 = 0; u8 < arr.length; u8++) {
  ({ key: arr[u8] }) = { key: 0 };
}
for (let u9 = 0; u9 < arr.length; u9++) {
  (arr[u9] as number)++;
}
for (let u10 = 0; u10 < arr.length; u10++) {
  (<number>arr[u10])++;
}
for (let u11 = 0; u11 < arr.length; u11++) {
  arr[u11]!!++;
}
for (let u12 = 0; u12 < arr.length; u12++) {
  (arr[u12]! satisfies number)++;
}
for (let u13 = 0; u13 < arr.length; u13++) {
  doMath(arr2[u13]);
}
for (let u14 = 0; u14 < arr.length; u14++) {
  u14++;
}
for (let u15 = 0; u15 < arr.length; u15++) {
  const copy = { u15 };
  doMath(copy.u15);
}
for (let u16 = 0; u16 < arr.length; u16 += 1) {
  arr[u16] += 1;
}
class Holder {
  items: number[] = [];
  *each() {
    for (let u17 = 0; u17 < this.items.length; u17++) {
      yield this.items[u17];
    }
    for (let u18 = 0; u18 < this.items.length; u18++) {
      yield this[u18];
    }
  }
  [key: number]: number;
}

export { Holder };
