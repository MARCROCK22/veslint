// Reported with enforceForTSTypes.
interface I {
  get x(): number;
  y: string;
  set x(v: number);
}
type T = {
  set z(v: number);
  get z(): number;
};

// Not reported.
interface J {
  get x(): number;
  set x(v: number);
}
