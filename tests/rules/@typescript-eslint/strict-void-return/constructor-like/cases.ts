// A generator named `constructor` is a method that overrides the base's.
class R {
  *constructor(): void {}
}
class S extends R {
  *constructor(): Promise<void> { return Promise.resolve(); }
}
export { S };
