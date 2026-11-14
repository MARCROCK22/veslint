declare function value(): number;
declare const enabled: boolean;
declare const extra: object;

// Arrays.
function a1() { const array = [1]; array.push(2, 3); return array; }
function a2() { const array = [1]; array.unshift(0); return array; }
function a3() { const array: number[] = []; array.push(value()); return array; }
function a4() { const array = [value()]; array.unshift(1); return array; }
function a5() { const array = [1]; array.push(2) /* c */; return array; }
function a6() { let array; array = [1]; array.push(2); return array; }
function a7() { const array = [1,]; array.push(2,); return array; }

// Objects.
function b1() { const object = { a: 1 }; object.b = 2; return object; }
function b2() { const object: Record<string, number> = {}; object['c' + 'd'] = 2; return object; }
function b3() { const object = { a: 1 }; object.b = value(); return object; }
function b4() { const object = { get a() { return 1; } }; object.b = 2; return object; }
function b5() { const key = '__proto__'; const object = {}; object[key] = 2; return object; }
function b6() { const object = { a: 1 }; Object.assign(object, { b: 2 }); return object; }
function b7() { const object = { a: 1 }; Object.assign(object, extra); return object; }
function b8() { const object = { a: 1 }; Object.assign(object, { b: value() }); return object; }
function b9() { const object = { a: 1 }; Object.assign(object, { b: 2 }, extra); return object; }

// Set and Map.
function c1() { const set = new Set([1]); set.add(2); return set; }
function c2() { const set = new Set(); set.add(2); return set; }
function c3() { const set = new WeakSet<object>; set.add(extra); return set; }
function c4() { const map = new Map([['a', 1]]); map.set('b', 2); return map; }
function c5() { const map = new Map<string, number>(); map.set('b', value()); return map; }

// Conditional mutations (not checked by default).
function d1() { const array = [1]; if (enabled) array.push(2); return array; }

// Initialization.
function e1() { let a: number; a = 1; return a; }
function e2() { let a; a = 1; return a; }
function e3() { let a: number, b: number; a = 1; return a + b; }
function e4() { let a: () => number; a = () => 1; return a; }
function e5() { let a: number; a = value(); return a; }
function e6() { let a, b; [a, b] = [1, 2]; return a + b; }
function e7() { var a: string; a = `x`; return a; }

// Not reported.
function k1() { const array = [1]; array.push(array.length); return array; }
function k2() { const array = [1]; other.push(2); return array; }
function k3() { const object = { a: 1 }; object.b += 2; return object; }
function k4() { const array = [1]; console.log(array); array.push(2); return array; }
function k5() { let a = 1; a = 2; return a; }
function k6() { const a = [1], b = 2; a.push(b); return a; }
declare const other: number[];
export { a1, a2, a3, a4, a5, a6, a7, b1, b2, b3, b4, b5, b6, b7, b8, b9, c1, c2, c3, c4, c5, d1, e1, e2, e3, e4, e5, e6, e7, k1, k2, k3, k4, k5, k6 };
