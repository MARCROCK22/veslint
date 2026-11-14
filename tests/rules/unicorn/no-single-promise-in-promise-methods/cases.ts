declare const promise: Promise<number>;
declare function read(): Promise<number>;
declare function use(value: unknown): void;

async function f() {
  // Fixed.
  await Promise.race([promise]);
  await Promise.all([promise]);
  const [first] = await Promise.all([read()]);
  const second = (await Promise.all([promise]))[0];
  let third: number;
  [third] = await Promise.all([promise]);
  await Promise.race([promise,]);
  // Reported, not fixed.
  const fourth = await Promise.all([promise]);
  const fifth = await Promise.all([read(/* c */)]);
  // Suggestions.
  use(Promise.race([promise]));
  use(Promise.any([promise]));
  await Promise.any([promise]);
  const sixth = Promise.race([promise, ]);
  const seventh = Promise.any([read()]);
  // Not reported.
  await Promise.all([promise, promise]);
  await Promise.all([...[promise]]);
  await Promise.allSettled([promise]);
  await Promise.all(promise as never);
  return [first, second, third, fourth, fifth, sixth, seventh];
}
export { f };
