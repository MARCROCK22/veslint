// A generator named `constructor` is a method: its assignments do not make a member readonly.
class P {
  private a = 1;
  *constructor() { this.a = 2; }
}
class Q {
  private b = 1;
  'constructor'() { this.b = 2; }
}
export { P, Q };
