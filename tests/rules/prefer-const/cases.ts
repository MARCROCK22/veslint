// Reported (and fixed when the whole declaration can change).
let a = 1;
let b = 2, c = 3;
let { d, e } = { d: 1, e: 2 };
let [f, g] = [1, 2];
let h;
h = 0;
for (let i of [1, 2]) {
  console.log(i);
}
for (let k in {}) {
  console.log(k);
}
let partial = 1, changed = 2;
changed = 3;
{
  let inBlock = 1;
  console.log(inBlock);
}
let readFirst;
console.log(readFirst);
readFirst = 1;

// Not reported.
let reassigned = 1;
reassigned = 2;
let neverWritten;
let { x, y } = { x: 1, y: 2 };
x = 3;
let outer = 0;
let inner;
({ inner, outer } = { inner: 1, outer: 2 });
for (let n = 0; n < 1; n++) {}
let late;
function setLate() {
  late = 1;
}
let objectTarget: { p?: number } = {};
let viaMember;
[viaMember, objectTarget.p] = [1, 2];
export { a, b, c, d, e, f, g, h, partial, changed, readFirst, reassigned, neverWritten, x, y, outer, inner, late, setLate, viaMember };
