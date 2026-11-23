declare const x: boolean;
declare function f(): number;
const a = x
  ? f()
  : await Promise.resolve(1);
const b = x
  ? {
      y: 1,
    }
  : 2;
const c = x
    ? new Date()
    : f();
export {};
