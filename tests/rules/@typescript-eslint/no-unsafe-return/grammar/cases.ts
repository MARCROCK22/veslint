// A comment with a line break ends the `return`: the `any` after it is not returned.
declare const anyValue: any;
function afterComment(): number | undefined {
  return /**
   * not returned
   */ anyValue;
}
function sameLine(): number {
  return /* one line */ anyValue;
}
function* afterYield(): Generator<number | undefined> {
  yield /* not yielded
  */ anyValue;
}
export { afterComment, sameLine, afterYield };
