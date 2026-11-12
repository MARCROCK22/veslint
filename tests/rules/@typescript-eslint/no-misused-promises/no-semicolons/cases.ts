// Cases without `;` and with end-of-line comments.
interface WithMethod { method(): void; field(): void } // comment
class Implementing implements WithMethod {
  async method() {} // comment
  field = async () => {} // comment
}
declare function withCallback(cb: () => void): void
const v: () => void = async () => {} // comment
withCallback(async () => {}) // comment
declare const aPromise: Promise<number>
if (aPromise) {} // comment
const o = { ...aPromise } // comment
void [Implementing, v, o]
