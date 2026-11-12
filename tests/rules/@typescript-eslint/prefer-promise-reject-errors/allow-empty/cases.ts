Promise.reject();
Promise.reject(undefined);
Promise.reject('text');
new Promise((resolve, reject) => {
  resolve(1);
  reject();
  reject(undefined);
});
