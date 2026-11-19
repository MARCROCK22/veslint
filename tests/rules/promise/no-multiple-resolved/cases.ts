// promise/no-multiple-resolved: an executor resolves its promise once on every path.
declare function check(): boolean;
declare function work(): number;

new Promise((resolve, reject) => {
  resolve(1);
  reject(new Error('x'));
});
new Promise((resolve, reject) => {
  if (check()) {
    resolve(1);
  }
  reject(new Error('x'));
});
new Promise((resolve, reject) => {
  if (check()) {
    resolve(1);
  } else {
    reject(new Error('x'));
  }
});
new Promise((resolve, reject) => {
  if (check()) {
    resolve(1);
    return;
  }
  reject(new Error('x'));
});
new Promise((resolve, reject) => {
  try {
    resolve(work());
  } catch (error) {
    reject(error);
  }
});
new Promise((resolve, reject) => {
  try {
    const value = work();
    resolve(value);
  } catch (error) {
    reject(error);
  }
  resolve(2);
});
new Promise((resolve) => {
  for (let i = 0; i < 3; i++) {
    resolve(i);
  }
});
new Promise((resolve, reject) => {
  check() ? resolve(1) : reject(2);
  resolve(3);
});
new Promise((resolve) => {
  check() && resolve(1);
  resolve(2);
});
new Promise(function (resolve, reject) {
  switch (work()) {
    case 1:
      resolve(1);
    case 2:
      reject(2);
      break;
    default:
      resolve(3);
  }
});
new Promise((resolve) => {
  setTimeout(() => {
    resolve(1);
    resolve(2);
  });
});
new Promise((resolve) => {
  resolve(1);
});
