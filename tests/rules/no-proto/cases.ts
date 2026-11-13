declare const o: any;

// Reported.
const a = o.__proto__;
o['__proto__'] = null;

// Not reported.
const b = Object.getPrototypeOf(o);
const c = { __proto__: null };
