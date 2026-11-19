// A generator or an accessor named `constructor` is a method.
class S {
  *constructor(): Promise<void> { return Promise.resolve(); }
  'constructor'(): Promise<void> { return Promise.resolve(); }
}
export { S };
