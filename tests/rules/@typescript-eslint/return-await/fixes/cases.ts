// return-await (default option, 'in-try-catch'): the fix and the suggestions.
// Non-ASCII text before the ranges: ñ 😀 日本語.
declare function p(): Promise<number>;
declare const prom: Promise<number>;
declare const maybe: Promise<number> | undefined;
declare const cond: boolean;
declare const n: number;

// Outside an error-handling context the `await` of a promise is removed, with the space after it.
async function a1() {
  return await p();
}
async function a2() {
  return await /* comment */ p();
}
async function a3() {
  return await
    p();
}
async function a4() {
  return (await p());
}
async function a5() {
  return await(p());
}
async function a6() {
  return cond ? await p() : await prom;
}
async function a7() {
  return cond ? (await p()) : cond ? await prom : (await (prom));
}
const a8 = async () => await p();
const a9 = async () => (cond ? await p() : n);
// An awaited value that is not a promise: always a fix.
async function b1() {
  return await n;
}
async function b2() {
  return await (n + 1);
}
async function b3() {
  try {
    return await 1;
  } catch {
    return await 'x';
  } finally {
    void 0;
  }
}
const b4 = async () => await n;

// In an error-handling context a promise must be awaited: only a suggestion.
async function c1() {
  try {
    return p();
  } catch (e) {
    return prom;
  } finally {
    void 0;
  }
}
async function c2() {
  try {
    return cond ? p() : prom;
  } catch {
    return 0;
  }
}
// Parentheses unless the expression binds tighter than `await`.
async function c3() {
  try {
    return maybe ?? p();
  } catch {
    return 0;
  }
}
async function c4() {
  try {
    return prom as Promise<number>;
  } catch {
    return 0;
  }
}
async function c5() {
  try {
    return (prom);
  } catch {
    return 0;
  }
}
async function c6() {
  try {
    return new Promise<number>(resolve => resolve(1));
  } catch {
    return 0;
  }
}
async function c7() {
  try {
    return prom!;
  } catch {
    return 0;
  }
}
async function c8() {
  try {
    return <Promise<number>>prom;
  } catch {
    return 0;
  }
}
async function c9(list: Promise<number>[]) {
  try {
    return list[0];
  } catch {
    return 0;
  }
}
async function c10() {
  try {
    return (cond, prom);
  } catch {
    return 0;
  }
}
async function c11() {
  try {
    return /* before */ p() /* after */;
  } catch {
    return 0;
  }
}
async function c12() {
  try {
    return p()
      .then(x => x);
  } catch {
    return 0;
  }
}

// Non-ASCII text on the same line.
async function ñ() { const 日本 = '😀'; return await p(); }
async function 語() { try { return '😀' ? prom : p(); } catch { return 0; } }
