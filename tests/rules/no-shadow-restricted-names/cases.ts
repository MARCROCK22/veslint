// Reported.
function NaN() {}
const Infinity = 1;
function f(undefined: number) {}
try {
} catch (eval) {}
let undefined2 = 1;
class globalThis {}
const g = function arguments() {};
const h = (NaN: number) => NaN;

// Not reported.
var undefined;
const k = 1;
