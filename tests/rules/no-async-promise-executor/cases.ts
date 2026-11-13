// Reported.
const a = new Promise(async (resolve) => resolve(1));
const b = new Promise(async function (resolve) {
  resolve(1);
});
const c = new Promise((async () => {}) as any);

// Not reported.
const d = new Promise((resolve) => resolve(1));
const e = new Promise(function (resolve) {
  resolve(1);
});
function shadow(Promise: any) {
  return new Promise(async () => {});
}
