// allowMixedPromiseArrays: an iterable passed to a promise aggregator may mix Promise and other
// values, as long as one of its values may be a Promise.
declare const p: Promise<number>;
declare const n: number;
declare const mixed: (number | Promise<number>)[];
declare const numbers: number[];
declare const tuple: [number, Promise<string>];
declare const numberTuple: [number, string];
declare const either: number[] | Promise<number>[];
declare const anything: any[];
declare const iterable: Iterable<number | Promise<number>>;
declare const numberIterable: Iterable<number>;
declare const generic: <T>(t: T) => T[];

async function f<T extends Promise<number>>(t: T) {
  await Promise.all([p, n]);
  await Promise.all([n, 1]);
  await Promise.all([n, t]);
  await Promise.all(mixed);
  await Promise.all(numbers);
  await Promise.allSettled(tuple);
  await Promise.race(numberTuple);
  await Promise.any(either);
  await Promise.all(anything);
  await Promise.all(iterable);
  await Promise.all(numberIterable);
  await Promise.all([n, ...numbers]);
  await Promise.all([...mixed, n]);
  await Promise.all(generic(p));
  await Promise.all([]);
}
export { f };
