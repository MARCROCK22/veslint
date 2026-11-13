// Reported.
new Promise((resolve) => resolve(1));
new Promise((resolve, reject) => {
  if (Math.random()) {
    return resolve(1);
  }
  return reject(new Error('x'));
});
new Promise(function (resolve) {
  return resolve(2);
});
new Promise((r) => void r(1));
new Promise((r) => (r(1), 2));
// Not reported.
new Promise((resolve) => {
  resolve(1);
});
new Promise((resolve) => {
  return;
});
new Promise((resolve) => {
  function inner() {
    return 1;
  }
  resolve(inner());
});
class Promise2 {}
export { Promise2 };
