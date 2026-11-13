declare let a: any;

// Not reported with exceptRange.
if (0 <= a && a < 10) {}
if (a < 0 || 10 <= a) {}
const b = (0 < a && a <= 1);

// Reported anyway.
if (0 <= a) {}
if (10 < a && a < 0) {}
