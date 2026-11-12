// Cases without `;` and with end-of-line comments.
declare function task(): Promise<number>
async function inTry() {
  try {
    return task() // the await is missing in a try
  } catch {
    return 0 // comment
  }
}
async function ordinary() {
  return await task() // the await is not needed
}
const arrow = async () => await task() // comment
void [inTry, ordinary, arrow]
