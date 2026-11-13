declare const a: string;

// Reported.
const a1 = 'a' + 'b';
const a2 = 'a' + `b`;
const a3 = a + 'b' + 'c';
const a4 = ('a') + ('b');
const a5 = 'a' + 'b' + a;

// Not reported.
const k1 = 'a' + a;
const k2 = 'a' +
  'b';
const k3 = 1 + 1;
const k4 = 'a' + 1;
