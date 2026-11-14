// return-await with 'never': in an error-handling context the removal of `await` is a suggestion.
declare function p(): Promise<number>;
declare const prom: Promise<number>;
declare const cond: boolean;
async function a1() {
  try {
    return await p();
  } catch {
    return await /* comment */ prom;
  } finally {
    void 0;
  }
}
async function a2() {
  try {
    return cond ? await p() : (await prom);
  } catch {
    return 0;
  }
}
async function a3() {
  return await p();
}
// typescript-eslint 8.72: an operand that starts an arrow function body with `{` gets parentheses.
declare const thenableObject: { then(cb: () => void): void };
const arrowObject = async () => await { then(cb: () => void) {} };
const arrowMember = async () => await { a: thenableObject }.a;
const arrowComment = async () => await /* comment */ { then(cb: () => void) {} };
const arrowParens = async () => (await { then(cb: () => void) {} });
const arrowTry = async () => {
  try {
    return await { then(cb: () => void) {} };
  } catch {
    return 0;
  }
};
void [arrowObject, arrowMember, arrowComment, arrowParens, arrowTry];
