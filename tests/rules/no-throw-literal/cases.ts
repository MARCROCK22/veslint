declare const e: Error, s: string, n: number | undefined;
declare function g(): Error;

// Reported.
function t1() { throw 'error'; }
function t2() { throw 0; }
function t3() { throw undefined; }
function t4() { throw null; }
function t5() { throw `${s}`; }
function t6() { throw 'a' + s; }
function t7() { throw { message: s }; }
function t8() { throw (s, 1); }
function t9() { let x: any; throw x += 1; }
function t10() { throw e as Error; }
function t11() { throw e!; }
function t12() { throw <Error>e; }
function t13() { throw e satisfies Error; }
function t14() { throw s && 'x'; }
function t15() { throw void 0; }
function t16() { throw [e]; }

// Not reported.
function k1() { throw e; }
function k2() { throw new Error(); }
function k3() { throw g(); }
function k4() { throw e.cause; }
function k5() { throw (s, e); }
function k6() { throw s || e; }
function k7() { throw n ? e : 1; }
async function k8() { throw await Promise.resolve(e); }
function* k9() { throw yield; }
function k10() { let x: any; throw x = e; }
function k11() { let x: any; throw x ||= e; }
function k12() { throw String.raw`a`; }
function k13() { throw g?.(); }
function k14() { const undefined = 1; throw undefined; }
export { t1, t2, t3, t4, t5, t6, t7, t8, t9, t10, t11, t12, t13, t14, t15, t16, k1, k2, k3, k4, k5, k6, k7, k8, k9, k10, k11, k12, k13, k14 };
