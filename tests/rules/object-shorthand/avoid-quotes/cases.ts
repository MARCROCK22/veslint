declare const a: number;

// Reported with avoidQuotes.
const o1 = { 'f'() {} };
const o2 = { g: function () {} };
const o3 = { a: a };

// Not reported.
const k1 = { 'h': function () {} };
const k2 = { 'a': a };
