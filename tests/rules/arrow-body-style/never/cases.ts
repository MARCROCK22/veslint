declare function g(): void;

// Reported with "never".
const f1 = () => {
  return 1;
};
const f2 = () => {};
const f3 = () => {
  g();
};
const f4 = () => {
  g();
  return 1;
};

// Not reported.
const k1 = () => 1;
