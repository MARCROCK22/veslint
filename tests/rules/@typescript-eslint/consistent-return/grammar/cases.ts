// A comment with a line break ends the `return`: it returns no value.
function afterComment(flag: boolean) {
  if (flag) {
    return /* the value
    of the flag */ 1;
  }
  return 2;
}
function sameLine(flag: boolean) {
  if (flag) {
    return /* one line */ 1;
  }
  return;
}
export { afterComment, sameLine };
