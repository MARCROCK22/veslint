declare const g: any;

// Reported (TypeScript reports most of them too).
const a = (Math as any)();
const b = new (JSON as any)();
const c = (Reflect as any)();
const m: any = Math;
const d = m();
const e = (globalThis.Math as any)();
const f = new (Intl as any)();

// Not reported.
const h = Math.max(1, 2);
const i = JSON.parse('1');
function shadow(Math: any) {
  return Math();
}

// globalThis is not a function (10.15.0).
const gt1 = () => (globalThis as any)();
const gt2 = () => new (globalThis as any)();
const gt3 = globalThis.structuredClone({});
const gt4 = globalThis.Math.max(1, 2);
