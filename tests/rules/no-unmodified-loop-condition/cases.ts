let node: { parent: unknown } | null = { parent: null };
let done = false;
let i = 0;
const limit = 10;

// Reported.
while (node) {
  doSomething(node);
}
while (done === false) {
  doSomething(i);
}
for (let j = 0; i < limit; j++) {}
do {
  doSomething(i);
} while (i < limit);
let a = 0, b = 1;
while (a < b) {
  doSomething(a);
}

// Not reported.
while (node) {
  node = null;
}
while (i < limit) {
  i++;
}
while (i < check()) {}
while (done ? i : limit) {
  done = true;
}
let c = 0, d = 1;
while (c < d) {
  c += 1;
}
let modifiedLater = 0;
while (modifiedLater < 3) {
  bump();
}
function bump() {
  modifiedLater++;
}
function doSomething(_: unknown) {}
function check() {
  return 1;
}
