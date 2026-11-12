// Cases without `;` and with end-of-line comments.
declare function syncFn(): number
async function withoutAwait() { return syncFn() } // comment
const arrow = async () => syncFn() // comment
class SomeClass {
  async method() { return 1 } // comment
  field = async () => { syncFn() } // comment
}
void [withoutAwait, arrow, SomeClass]
