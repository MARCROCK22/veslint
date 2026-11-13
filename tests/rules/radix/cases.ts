// Reported.
const a = parseInt('10');
const b = parseInt();
const c = parseInt('10', 1);
const d = parseInt('10', 37);
const e = parseInt('10', undefined);
const f = Number.parseInt('10');
const g = parseInt('10',);
const h = parseInt('10', '16' as any);
const i = Number.parseInt('10', 0);

// Not reported.
const j = parseInt('10', 10);
const k = parseInt('10', 16.0);
const l = Number.parseInt('10', 8);
const m = parseInt('10', radix);
declare const radix: number;
function shadow(parseInt: any) {
  return parseInt('10');
}
