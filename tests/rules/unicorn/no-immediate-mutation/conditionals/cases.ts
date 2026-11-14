declare const enabled: boolean;
declare const value: number;

function a1() { const array = [1]; if (enabled) array.push(2); return array; }
function a2() { const array = [1]; if (enabled) { array.push(2); } else { array.push(3); } return array; }
function a3() { const array = [1]; enabled && array.push(2); return array; }
function a4() { const array = [1]; enabled ? array.push(2) : array.push(3); return array; }
function a5() { const array = [1]; if (enabled) array.push(2); else array.unshift(3); return array; }
function a6() { const object: Record<string, number> = {}; if (enabled) object.a = 1; return object; }
function a7() { const set = new Set<number>(); if (enabled) set.add(value); return set; }
function a8() { const map = new Map<string, number>(); if (enabled) map.set('a', value); return map; }
function a9() { const array = [1]; if (array.length) array.push(2); return array; }
function a10() { const object = {}; if (enabled) Object.assign(object, { a: 1 }); return object; }
export { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 };
