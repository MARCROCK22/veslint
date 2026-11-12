// Inline configurations whose options do not fit the schema of the rule: ESLint reports each with
// the errors of its schema validator, and the comment changes nothing.
/* eslint @typescript-eslint/no-floating-promises: ["error", {"ignoreVoid": "yes", "nope": 1}] */
/* eslint @typescript-eslint/await-thenable: ["error", {"anything": true}] */
/* eslint @typescript-eslint/return-await: [2, "sometimes"] */
/* eslint @typescript-eslint/restrict-template-expressions: ["warn", {allow: ["Error", {from: "package", name: ["a", "a"]}]}] */
/* eslint @typescript-eslint/no-misused-promises: [1, {checksVoidReturn: {arguments: 1}}], @typescript-eslint/unbound-method: [2, null] */
// The options go over the default ones of the rule's meta before they are validated.
/* eslint @typescript-eslint/dot-notation: [2, {allowPattern: "^x", allowKeyword: false}] */
// Turned off with "off", the options are validated all the same; with 0 they are not.
/* eslint @typescript-eslint/no-array-delete: ["off", 1] */
/* eslint @typescript-eslint/no-for-in-array: [0, 1] */
// With only a severity the options are those of the configuration, which ESLint had not validated
// for a rule that was off there.
/* eslint @typescript-eslint/no-meaningless-void-operator: "error" */
/* eslint @typescript-eslint/no-base-to-string: 0 */
// Options that fit: `failureMessage` is in the schema of the rule, which does nothing with it.
/* eslint @typescript-eslint/naming-convention: [2, {selector: "variable", format: ["UPPER_CASE"], failureMessage: "x"}] */
declare const p: Promise<number>;
declare const list: number[];
async function f() {
  void p;
  p;
  await 1;
  delete list[0];
  for (const key in list) {
    void key;
  }
  const lower = void 0;
  return lower;
}
export { f };
