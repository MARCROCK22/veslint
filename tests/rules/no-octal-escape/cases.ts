// Not reported (TypeScript rejects octal escapes, which this rule reports).
const k1 = '\0';
const k2 = '\\1';
const k3 = '\u0001';
const k4 = '\x01';
