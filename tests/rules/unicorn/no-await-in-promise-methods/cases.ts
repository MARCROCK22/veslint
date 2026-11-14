declare const promise: Promise<number>;
declare const other: Promise<number>;

async function f() {
  // Reported, with a suggestion.
  await Promise.all([await promise, other]);
  await Promise.allSettled([await promise]);
  await Promise.any([other, await   promise]);
  await Promise.race([await promise]);
  // Reported, no suggestion (not the element itself).
  await Promise.all([(await promise) + 1]);
  await Promise.all([{ value: await promise }]);
  // Not reported.
  await Promise.all([promise, other]);
  await Promise.all([async () => await promise]);
  await Promise.all([await promise, other], 1 as never);
  await Promise.all?.([await promise]);
  await Promise['all']([await promise]);
}
export { f };
