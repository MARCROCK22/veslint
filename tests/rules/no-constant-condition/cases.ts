declare let a: any;
declare let b: any;
declare function f(): any;

// Reported: a test whose truthiness never changes.
if (true) {}
if (0) {}
if ('') {}
if (`text${a}`) {}
if (`${1}`) {}
if ([]) {}
if ({}) {}
if (() => {}) {}
if (function () {}) {}
if (class {}) {}
if (new Date()) {}
if (typeof a) {}
if (void a) {}
if (!true) {}
if (-1) {}
if (1 + 2) {}
if (a || true) {}
if (false && a) {}
if (a && false) {}
if ((a = 1)) {}
if ((a, 1)) {}
if (Boolean(1)) {}
if (Boolean()) {}
if (undefined) {}
if (a ||= true) {}
if (/re/) {}
if (0n) {}
const t1 = true ? 1 : 2;
const t2 = [] ? 1 : 2;
while (1) {}
while (false) {}
do {} while (true);
for (; 1; ) {}
for (; [] ; ) {}
if (`\
`) {}

// Not reported.
if (a) {}
if (f()) {}
if (a === 1) {}
if ('a' in b) {}
if (a || b) {}
if (true || a) {}
while (true) {}
for (;;) {}
if (Boolean(a)) {}
if (Boolean?.(1)) {}
if (`${a}`) {}
if (a ||= b) {}
if (a += 1) {}
if (new Date() as any) {}
if (a!) {}
function* gen() {
  while (1) {
    yield;
  }
  for (; true; ) {
    yield 1;
  }
  do {
    yield;
  } while (1);
}
function shadow(Boolean: (x: unknown) => boolean, undefined: unknown) {
  if (Boolean(1)) {}
  if (undefined) {}
}
