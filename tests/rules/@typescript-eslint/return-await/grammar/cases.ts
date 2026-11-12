// A comment with a line break ends the `return` (it counts as a line break for the automatic
// semicolon), so the `await` after it is not returned.
async function afterComment(p: Promise<number>) {
  return /* the result
  of the wait */ await p;
}
async function afterDoc(p: Promise<number>) {
  return /**
   * the result
   */ await p;
}
async function sameLine(p: Promise<number>) {
  return /* one line */ await p;
}
async function nextLine(p: Promise<number>) {
  return /* one line */
  await p;
}
export { afterComment, afterDoc, sameLine, nextLine };
