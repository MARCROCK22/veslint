// Reported.
let counter = 0;
for (var i = 0; i < 3; i++) {
  setTimeout(function () {
    console.log(i);
  });
  setTimeout(() => i + counter);
}
counter++;
let total = 0;
while (total < 10) {
  const add = () => total;
  total += add();
}
for (let j = 0; j < 3; j++) {
  class C {
    m() {
      return total;
    }
  }
  new C();
}
for (const x of [1, 2]) {
  (function named() {
    console.log(total, named);
  })();
}

// Not reported.
for (let k = 0; k < 3; k++) {
  setTimeout(() => k);
}
const fixed = 1;
for (const y of [1]) {
  setTimeout(() => y + fixed);
}
for (let m = 0; m < 3; m++) {
  (() => total)();
  (function () {
    return total;
  })();
}
let never = 1;
for (;;) {
  setTimeout(() => never);
  break;
}
async function later() {
  for (let n = 0; n < 1; n++) {
    await (async () => total)();
  }
}
export { later, never };
