function* g1() {
  yield*[1];
  yield * [2];
  yield *[3];
  yield* [4];
  yield/* c */*/* d */[5];
  yield /* c */ * /* d */ [6];
  yield*
    [8];
  yield [9];
  yield;
  const x = yield*g1();
  return (yield*[x]);
}
const o = { *m() { yield*[1]; } };
class C { *m() { yield *[1]; } async *n() { yield* [1]; } }
