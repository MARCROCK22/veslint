// no-unsafe-assignment with noImplicitThis disabled.
function withThis() {
  const me = this;
  const member = this.a;
  let other: number;
  other = this.b;
  return [me, member, other];
}
void withThis;
