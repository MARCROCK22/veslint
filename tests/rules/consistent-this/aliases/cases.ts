// Reported with the aliases "self" and "me".
function f(this: any) {
  const that = this;
  const self = 1;
  return [that, self];
}

// Not reported.
function g(this: any) {
  const self = this;
  const me = this;
  return [self, me];
}
