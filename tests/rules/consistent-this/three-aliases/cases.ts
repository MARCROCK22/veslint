// Reported: each alias must be `this` (three aliases: all of them are checked).
function f(this: any) {
  const context = 1;
  const me = 2;
  const self = 3;
  return [context, me, self];
}

// Not reported.
function g(this: any) {
  const context = this;
  const me = this;
  const self = this;
  return [context, me, self];
}
export { f, g };
