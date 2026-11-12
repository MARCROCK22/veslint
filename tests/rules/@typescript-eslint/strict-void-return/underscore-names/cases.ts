// A member of a class is compared with the member of the same name of what the class extends or
// implements. TypeScript keeps a name that starts with two underscores with one more, and the
// name the rule looks up is the one as written.
interface Names {
  plain(): void;
  _one(): void;
  __two(): void;
  ___three(): void;
  ____four(): void;
  '__quoted'(): void;
  __property: () => void;
}
class Implements implements Names {
  async plain() {}
  async _one() {}
  async __two() {}
  async ___three() {}
  async ____four() {}
  async '__quoted'() {}
  __property = async () => {};
}
abstract class Base {
  abstract __method(): void;
  __field: () => void = () => {};
  __other(): Promise<void> {
    return Promise.resolve();
  }
}
class Extends extends Base {
  async __method() {}
  __field = async () => {};
  async __other() {}
}
export { Implements, Extends };
