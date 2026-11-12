declare const promise: Promise<number>;

promise.catch(e => e);
promise.catch(async e => e);
promise.catch((e) => e);
promise.catch(( e ) => e);
promise.catch((e /* inner */) => e);
promise.catch((e?) => e);
promise.catch((e ?) => e);
promise.catch((e: any) => e);
promise.catch((e : any) => e);
promise.catch((e?: any) => e);
promise.catch((e: Error | string) => e);
promise.catch(
  (
    e: {
      message: string;
    },
  ) => e,
);
promise.catch((e = 1) => e);
promise.catch((e: any = 1) => e);
promise.catch((e, extra?: number) => [e, extra]);
promise.catch(function (e) {
  return e;
});
promise.catch(function (e: any) {
  return e;
});
promise.catch(function (this: void, e) {
  return e;
});
promise.catch(function (this, e) {
  return [this, e];
});
promise.catch((...args) => args);
promise.catch((...args: any[]) => args);
promise.catch((...args: [any]) => args);
promise.catch((... args /* c */ ) => args);
promise.catch(({ message }) => message);
promise.catch(([first]) => first);
promise.then(v => v, e => e);
promise.then(v => v, (e: any) => e);
const résumé = '🎉é'; promise.catch(é => é);
promise.catch(日本 => 日本);
void [résumé];
