// Disable directives in a file whose lines end at U+2028, at U+2029, at a lone CR and at CRLF:
// ESLint counts each of them as a line break (see tests/rules/no-floating-promises/line-breaks).
declare const p: Promise<number>;
async function f() {
  // eslint-disable-next-line @typescript-eslint/no-floating-promises   p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises   p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises   p;   p;   p;  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises
  p;
  // eslint-disable-next-line @typescript-eslint/no-floating-promises    p;
  p; // eslint-disable-line @typescript-eslint/no-floating-promises   p;
  p; // eslint-disable-line @typescript-eslint/no-floating-promises   p;
  p; // eslint-disable-line @typescript-eslint/no-floating-promises  p;
  p;  p; // eslint-disable-line @typescript-eslint/no-floating-promises
  p;   p; /* eslint-disable-line @typescript-eslint/no-floating-promises */ p;   p;
  p; /* eslint-disable-line @typescript-eslint/no-floating-promises --  two lines */
  p; /* eslint-disable-line @typescript-eslint/no-floating-promises --  two lines */
  p; /* eslint-disable-line @typescript-eslint/no-floating-promises -- two lines */
  p; /* eslint-disable-line @typescript-eslint/no-floating-promises --
 two lines */
  /* eslint-disable-next-line @typescript-eslint/no-floating-promises --  ends here */ p;   p;  p;
  p; /* eslint-disable @typescript-eslint/no-floating-promises */  p;   /* 😀 */ p; /* eslint-enable @typescript-eslint/no-floating-promises */ p;   p;
  void 0;  // eslint-disable-next-line @typescript-eslint/no-floating-promises   void 0;   void 0; // eslint-disable-line  /* 😀 */ /* eslint-disable-next-line */ void 0;
}
void f;
