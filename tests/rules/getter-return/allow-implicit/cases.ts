// Reported: no return at all.
class A {
  get a(): number | undefined {
    console.log('a');
  }
}
// Not reported: an empty return is allowed.
class B {
  get b(): number | undefined {
    return;
  }
  get c(): number | undefined {
    if (Math.random()) {
      return 1;
    }
    return;
  }
}
export { A, B };
