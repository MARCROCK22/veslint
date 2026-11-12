declare const promise: Promise<number>;
declare function getPromise(): Promise<number>;
declare const cond: boolean;

async function main() {
  void promise;
  void getPromise();
  (void promise);
  void (promise);
  void void promise;
  void /* comment */ promise;
  void
    getPromise();
  promise;
  (promise);
  cond ? promise : getPromise();
  void (cond ? promise : getPromise());
  void promise, 1;
  1, void promise;
  getPromise().then(() => {}, undefined);
  void getPromise().then(() => {}, null);
  [promise];
  void [promise];
  const résumé = '🎉é'; void promise;
  void résumé;
}
void main;
