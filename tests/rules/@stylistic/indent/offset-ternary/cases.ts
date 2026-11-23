declare const x: boolean;
declare function f(): number;
const a = x
  ? f()
  : 1;
const b = x
  ? {
      y: 1,
    }
  : [
      2,
    ];
const c = x
  ? new Date()
  : await Promise.resolve(1);
export {};
function wrong() {
      return 1;
}
const d = x
    ? f()
  : (
    1
  );
