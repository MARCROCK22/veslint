// A module: its declarations are not global, but the lib's globals are read-only.
var a = 1;
function f() {}
class C {}
let b = 2;

// Reported.
Object = null as any;
for (Array of []) {
}
undefined;

// Not reported.
JSON.stringify(a);
export { f, C, b };
