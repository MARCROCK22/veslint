// Reported.
function a() {
  return arguments;
}
function b() {
  return Array.from(arguments);
}
const c = function () {
  return arguments[0];
};
function d() {
  const f = () => arguments;
  return f;
}
class K {
  m() {
    return arguments;
  }
}

// Not reported.
function e() {
  return arguments.length;
}
function g(...args: unknown[]) {
  return args;
}
function h(arguments: unknown) {
  return arguments;
}
