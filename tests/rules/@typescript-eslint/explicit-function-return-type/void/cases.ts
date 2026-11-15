// Not reported: a concise body starting with void.
const a = () => void 0;
const b = (x: unknown) => void console.log(x);
// Reported.
const c = () => {
  void 0;
};
const d = () => (void 0, 1);
const e = function () {
  return void 0;
};
