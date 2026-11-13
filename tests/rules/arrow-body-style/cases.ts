declare const a: any;
declare function g(): void;

// Reported with "as-needed".
const f1 = () => {
  return 1;
};
const f2 = () => { return { x: 1 }; };
const f3 = () => {
  return a, 1;
};
const f4 = () => {
  // comment
  return a;
};
const f5 = (): number => {
  return 1;
};
const f6 = () => {
  return;
};
const f7 = () => { return a }
[1].map(g);
for (const f8 = () => { return 'x' in a; }; ; ) {}

// Not reported.
const k1 = () => 1;
const k2 = () => {
  g();
};
const k3 = () => {
  g();
  return 1;
};
const k4 = () => {};
