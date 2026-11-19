// promise/prefer-catch: `catch(b)` rather than `then(a, b)` or `then(null, b)`.
declare const promise: Promise<number>;
declare function onValue(value: number): void;
declare function onError(error: unknown): void;

promise.then(onValue, onError);
promise.then(null, onError);
promise.then(undefined, onError);
promise.then(onValue, (error) => {
  onError(error);
});
promise.then((onValue), (onError));
promise.then(onValue, onError,);
promise.then(null, onError, 3);
promise.then(onValue, onError).then(null, (error) => onError(error));
promise?.then(onValue, onError);
promise.then(onValue);
promise.catch(onError);
promise['then'](onValue, onError);
promise.then(/* first */ onValue, /* second */ onError);
