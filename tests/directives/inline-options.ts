// An inline configuration with options, in the forms ESLint accepts.
/* eslint @typescript-eslint/no-floating-promises: ["error", {"ignoreVoid": false}] */
/* eslint "@typescript-eslint/await-thenable": off, '@typescript-eslint/no-array-delete': 'warn' -- reason */
/* eslint @typescript-eslint/no-unsafe-member-access: [2, { allowOptionalChaining: true }] */
declare const p: Promise<number>;
declare const anything: any;
declare const list: number[];
async function f() {
  void p;
  await 1;
  delete list[0];
  anything?.a;
  anything.b;
}
export { f };
