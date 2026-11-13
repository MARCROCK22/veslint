// Reported.
const a1 = parseInt('111110111', 2);
const a2 = Number.parseInt('767', 8);
const a3 = parseInt('1F7', 16);
const a4 = parseInt(`1F7`, 16);
const a5 = parseInt('0x1F7', 16);
const a6 = parseInt('12', 2);
const a7 = 1+parseInt('11', 2);
const a8 = parseInt(/* c */ '11', 2);

// Not reported.
const k1 = parseInt('111', 10);
const k2 = parseInt(x, 2);
const k3 = parseInt('111', 3);
const k4 = Math.parseInt('111', 2);
declare const x: string;
