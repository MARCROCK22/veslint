let a: number = 1;
var b, c = 1, d: string = '', e: number;
const f = 1;
let [g] = [1];
let { h } = { h: 1 };
for (let i = 0; i < 1; i++) { let j: number = i; void j; }
for (const k of [1]) { void k; }
for (let l of [1]) { void l; }
for (var m in {}) { void m; }
for (let n; ; ) { break; }
declare let o: number;
declare namespace NS1 {
  let p: number;
}
namespace NS2 {
  let q = 1;
}
declare namespace NS3 {
  declare namespace NS4 {}
  let r = 1;
}
let s:
  string = 'x';
export { a, b, c, d, e, f, g, h, o, NS1, NS2, NS3, s };
