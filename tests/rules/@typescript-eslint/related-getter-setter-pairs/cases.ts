export {};
declare function logged(value: unknown, context: ClassGetterDecoratorContext): void;
const key = 'computed';

class Mismatched {
  get value(): string {
    return '';
  }
  set value(input: number) {}
}

class Matching {
  get value(): string {
    return '';
  }
  set value(input: string) {}
  get wide(): string {
    return '';
  }
  set wide(input: string | number) {}
  get unknownInput(): number {
    return 0;
  }
  set unknownInput(input: unknown) {}
  get inferred(): number {
    return 0;
  }
  set inferred(input) {}
}

class Narrower {
  get value(): string | number {
    return '';
  }
  set value(input: string) {}
}

class WithoutReturnType {
  get value() {
    return '';
  }
  set value(input: number) {}
}

class Names {
  get #secret(): string {
    return '';
  }
  set #secret(input: number) {}
  get 'quoted'(): string {
    return '';
  }
  set quoted(input: number) {}
  get 1(): string {
    return '';
  }
  set '1'(input: number) {}
  get [key](): string {
    return '';
  }
  set computed(input: number) {}
  static get shared(): string {
    return '';
  }
  set shared(input: number) {}
}

class Decorated {
  @logged
  get value(): (string) {
    return '';
  }
  set value(input: number) {}
}

class Destructured {
  get point(): { x: string } {
    return { x: '' };
  }
  set point({ x }: { x: number }) {}
}

declare class Ambient {
  get value(): string;
  set value(input: number);
}

abstract class Abstract {
  abstract get value(): string;
  abstract set value(input: number);
}

interface Contract {
  get value(): string;
  set value(input: number);
  get same(): string;
  set same(input: string);
}

type Literal = {
  get value(): string,
  set value(input: number),
};

const objectLiteral = {
  get value(): string {
    return '';
  },
  set value(input: number) {},
};

const Expression = class {
  get value(): boolean {
    return true;
  }
  set value(input: number) {}
  method(): void {
    class Inner {
      get inner(): number {
        return 0;
      }
      set inner(input: string) {}
    }
  }
};

class ComputedNames {
  // getNameFromMember names a computed identifier key by the identifier.
  get [key](): string {
    return '';
  }
  set key(input: number) {}
  get ['dashed-name'](): string {
    return '';
  }
  set 'dashed-name'(input: number) {}
  get [`template`](): string {
    return '';
  }
  set template(input: number) {}
}

class LastOneWins {
  get value(): number {
    return 0;
  }
  get value(): string {
    return '';
  }
  set value(input: string) {}
}
