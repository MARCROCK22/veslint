declare const fn: any;

// Reported.
(Object.prototype as any).a = 1;
(Array.prototype as any)['b'] = fn;
Object.defineProperty(Number.prototype, 'c', { value: 1 });
Object.defineProperties(String.prototype, { d: { value: 1 } });
(Object.prototype as any).e += 1;

// Not reported.
const p = Object.prototype;
fn.prototype.a = 1;
Object.defineProperty(fn.prototype, 'c', { value: 1 });
