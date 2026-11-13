declare const a: any;

// Reported with "always".
const f1 = () => 1;
const f2 = () => ({ x: 1 });
const f3 = () => (
  { x: 1 }
);
const f4 = async (b: number) => b + a;

// Not reported.
const k1 = () => {
  return 1;
};
