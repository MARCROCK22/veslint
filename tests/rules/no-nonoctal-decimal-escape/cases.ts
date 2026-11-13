// Not reported (TypeScript rejects `\8` and `\9`, which this rule reports).
const k1 = '8';
const k2 = '\\8';
const k3 = `\\8`;
const k4 = '\0';
