// Reported.
const a1 = [, 1];
const a2 = [1, , 2];
const a3 = [1, , , 2];
const a4 = [,];
const a5 = [, , ];
const a6 = [1, /* c */ , 2];

// Not reported.
const k1 = [1, 2];
const k2 = [1, 2,];
const k3: number[] = [];
