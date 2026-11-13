// Reported (TypeScript reports them too).
function a(x: number, x: number) {}
const b = function (y: number, z: number, y: number, z: number) {};
function c(d: number, d: number, d: number) {}

// Not reported.
function e(x: number, y: number) {}
const f = (x: number, y: number) => x + y;
function g(x: number, { x: y }: { x: number }) {}
