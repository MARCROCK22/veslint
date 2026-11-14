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

// Signs, spreads and computed `Number['parseInt']` (10.15.0).
declare const args: [string, number];
const n1 = parseInt('10', -1);
const n2 = parseInt('10', +37);
const n3 = parseInt('10', -0);
const n4 = parseInt('10', +10.5);
const n5 = Number['parseInt']('10');
const n6 = Number[`parseInt`]('10', 1);
const n7 = Number?.['parseInt']('10');
const n8 = parseInt('10', 1, ...[]);
const k1 = parseInt('10', +10);
const k2 = parseInt('10', +0x10);
const k3 = parseInt('10', +'10');
const k4 = parseInt('10', ~1);
const k5 = parseInt('10', -radix);
const k6 = parseInt(...args);
const k7 = Number.parseInt('10', ...[10]);
const k8 = Number['parseInt']('10', 16);
