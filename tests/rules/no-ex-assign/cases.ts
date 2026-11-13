declare let x: any;

// Reported.
try {
} catch (e) {
  e = 10;
}
try {
} catch ({ message }) {
  message = 'x';
}
try {
} catch (e) {
  [e] = x;
}

// Not reported.
try {
} catch (e) {
  const f = e;
}
