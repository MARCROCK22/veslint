// promise/no-promise-in-callback with exemptDeclarations.
declare const promise: Promise<number>;
declare function handle(value: unknown): void;

function onDone(err: Error | null) {
  promise.then(handle);
}
const onFail = (err: Error) => {
  promise.then(handle);
};
export { onDone, onFail };
