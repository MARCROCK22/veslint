// Disable directives: which findings they suppress and which of them are unused.
declare const p: Promise<number>;
declare const list: number[];
async function f() {
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  p;
  p; // eslint-disable-line @typescript-eslint/no-floating-promises
  // eslint-disable-next-line
  p;
  p; // eslint-disable-line
  /* eslint-disable-next-line @typescript-eslint/no-floating-promises -- with a reason */
  p;
  // eslint-disable-next-line @typescript-eslint/await-thenable
  p;
  /* eslint-disable @typescript-eslint/no-floating-promises */
  p;
  await 1;
  /* eslint-enable @typescript-eslint/no-floating-promises */
  p;
  /* eslint-disable */
  p;
  await 1;
  delete list[0];
  /* eslint-enable */
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises, @typescript-eslint/await-thenable
  p;
  // eslint-disable-next-line @typescript-eslint/no-array-delete, @typescript-eslint/await-thenable
  p;
  // eslint-disable-next-line @typescript-eslint/no-array-delete, @typescript-eslint/await-thenable, @typescript-eslint/prefer-find
  void 0;
  // eslint-disable-next-line '@typescript-eslint/no-floating-promises', "@typescript-eslint/await-thenable"
  p;
  /*
    eslint-disable-next-line @typescript-eslint/no-floating-promises
  */
  p;
  p; /* eslint-disable-line
    @typescript-eslint/no-floating-promises */
  // eslint-disable-next-line no-such-rule
  p;
  // eslint-disable-next-line @typescript-eslint/no-such-rule, @typescript-eslint/no-floating-promises
  p;
  // eslint-disable @typescript-eslint/no-floating-promises
  p;
  /* eslint-enable @typescript-eslint/no-floating-promises */
  /* eslint-enable */
  // eslint-disable-next-line no-console
  p;
  //eslint-disable-next-line @typescript-eslint/no-floating-promises
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises -- ñ non-ASCII reason 😀
  p;
  const emoji = '😀'; p; // eslint-disable-line @typescript-eslint/no-floating-promises
  // eslint-disable-next-line-not-a-directive
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises --no space, so not a reason
  p;
  return emoji;
}
export { f };
