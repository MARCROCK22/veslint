let a: number;
var b, c = 1, d: string;
let e!: number;
let ünïcödé: number;
let 𝒳: number;
let [f] = [1];
let { g } = { g: 1 };
const h = 1;
for (let i; i! < 1; ) { break; }
for (let j = 0; j < 1; j++) { let k: number; void k; }
for (const l of [1]) { void l; }
for (const m in {}) { void m; }
for (var n; ; ) { break; }
declare let o: number;
declare namespace NS1 {
  let p: number;
  namespace Inner {
    let q: number;
  }
  const r: number;
}
declare global {
  var s: number;
}
declare module 'foo' {
  let t: number;
}
namespace NS2 {
  let u: number;
  export let v: number;
}
declare namespace NS3 {
  declare namespace NS4 {}
  let w: number;
}
let x2:
  number;
function f1() {
  let y: string;
  var z;
  return [y, z];
}
class C {
  static {
    let aa: number;
    void aa;
  }
}
export { a, b, c, d, e, ünïcödé, 𝒳, f, g, h, n, o, NS1, NS2, NS3, x2, f1, C };
