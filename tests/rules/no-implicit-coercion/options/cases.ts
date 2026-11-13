declare const a: any;

// Reported with disallowTemplateShorthand and some operators allowed.
const s1 = `${a}`;
const n1 = +a;

// Not reported.
const b1 = !!a;
const s2 = '' + a;
const s3 = `x${a}`;
const s4 = `${String(a)}`;
