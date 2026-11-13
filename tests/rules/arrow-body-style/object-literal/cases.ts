// Reported with requireReturnForObjectLiteral.
const f1 = () => ({ x: 1 });
const f2 = () => {
  return 1;
};

// Not reported.
const k1 = () => {
  return { x: 1 };
};
const k2 = () => 1;
