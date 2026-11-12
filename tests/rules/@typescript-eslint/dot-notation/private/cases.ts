// dot-notation with allowPrivateClassPropertyAccess: true.
declare function decorate(target: object, key: string): void;

class Base {
  protected guarded = 1;
}

export class Secret extends Base {
  private hidden = 1;
  private static shared = 2;
  static readonly constant = 3;
  @decorate private decorated = 4;
  declare private declared: number;
  public open = 5;
  plain = 6;
  #truly = 7;
  private method(): number {
    return this.#truly;
  }

  constructor(private param: number) {
    super();
  }

  read(other: Secret, maybe: Secret | undefined): number {
    // Not reported: private members, also through a union, `!` and parentheses.
    return (
      this['hidden'] +
      other['hidden'] +
      maybe!['hidden'] +
      (maybe?.['hidden'] ?? 0) +
      this[`hidden`] +
      this[('hidden')] +
      Secret['shared'] +
      this['decorated'] +
      this['param'] +
      this['method']() +
      // Reported: other modifiers come first or are not private.
      this['declared'] +
      Secret['constant'] +
      this['open'] +
      this['plain'] +
      this['guarded']
    );
  }
}

const instance = new Secret(1);
// Not reported: a private member from outside the class.
// @ts-expect-error -- `hidden` is private.
void instance['hidden'];
// Reported: a property of a library type and of an object literal.
void [1]['length'];
void { hidden: 1 }['hidden'];
