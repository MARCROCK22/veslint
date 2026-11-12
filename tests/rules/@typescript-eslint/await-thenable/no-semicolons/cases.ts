// Cases without `;` and with end-of-line comments.
declare function syncFn(): number
declare const list: number[]
async function noSemicolon() {
  await syncFn() // comment
  await 1 /* block */
  for await (const n of list) { void n } // comment
  await Promise.all([1, syncFn()]) // comment
}
void noSemicolon
