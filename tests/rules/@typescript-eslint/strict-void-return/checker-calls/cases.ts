// Cases of strict-void-return where the answer depends on the node the type of a parameter is
// asked at (getTypeOfSymbolAtLocation): `run` is the parameter of the signature it calls, and the
// call is where it is narrowed.
declare function isOuter(x: unknown): x is typeof outer;
function outer(run: typeof outer | (() => number)): void {
  if (isOuter(run)) {
    run(() => 1);
    (run)(() => 1);
    const copy = run;
    copy(() => 1);
  }
}
void outer;
