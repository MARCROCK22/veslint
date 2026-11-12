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
