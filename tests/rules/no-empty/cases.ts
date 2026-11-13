declare const a: boolean;
declare function f(): void;

// Reported.
if (a) {}
if (a) {
} else {
}
while (a) {}
for (;;) {}
try {
} catch (e) {
} finally {
}
{}
switch (a) {}
switch (a) {
}
label: {}

// Not reported.
function g() {}
const h = () => {};
const i = function () {};
class K {
  m() {}
  static {}
  constructor() {}
}
const o = { m() {}, get x() { return 1; } };
if (a) {
  // comment
}
if (a) { /* comment */ }
switch (a) {
  // comment
}
switch (a) {
  case true:
}
declare global {}
namespace N {}
declare module 'm' {}
try {
  f();
} catch {
  f();
}

// A comment after the braces is not inside them.
if (a) {} /* after */
switch (a) {} // after
