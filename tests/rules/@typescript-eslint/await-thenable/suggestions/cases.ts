declare const value: number;
declare const list: number[];
declare const syncRes: Disposable;
declare const asyncRes: AsyncDisposable;
declare function open(): Disposable;

async function main() {
  await value;
  await (value);
  await /* comment */ value;
  await
    value;
  await await value;
  const sum = (await value) + (await 1);
  void [await value, await 'text'];
  for await (const item of list) {
    void item;
  }
  for /* a */ await /* b */ (const item of list) {
    void item;
  }
  for
  await
  (const item of [1, 2]) {
    void item;
  }
  await using one = syncRes;
  await using two = open(), three = syncRes;
  await using four = asyncRes, five = syncRes;
  await /* c */ using six = (syncRes);
  await using seven: Disposable = open();
  const résumé = '🎉é'; await value;
  void [sum, résumé];
}
void main;

// typescript-eslint 8.72: the removal takes what follows `await` up to the next token or comment,
// and an operand that would start an arrow function body or a statement with `{`, `class` or
// `function` gets parentheses.
declare const record: { a: number };
async function wrapped() {
  await   value;
  await	/* kept */ value;
  await {};
  await { a: 1 }.a;
  await class {};
  await function () {}.name;
  (await {}).toString();
  const arrow = async () => await { a: 1 };
  const arrowMember = async () => await {}.constructor;
  const arrowParen = async () => (await {});
  const arrowSequence = async () => await {}, other = 1;
  const arrowNested = async () => await await {};
  await (async () => {})() satisfies Promise<void> | undefined, await {} ?? 0;
  await record;
  void [arrow, arrowMember, arrowParen, arrowSequence, other, arrowNested];
}
void wrapped;
