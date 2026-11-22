// The names after `import('…')` in a type are the qualifier of a TSImportType (an Identifier or a
// TSQualifiedName), no member access: they read no member.
export class C {
  private foo = 1;
  private bar = 2;
  private baz = 3;
  m(): typeof import('./cases').foo {
    return this.bar as never;
  }
  n(): typeof import('./cases').C.prototype.baz {
    return 0 as never;
  }
}
export const foo = 1;
export class D {
  private qux = 1;
  private quux = 2;
  m(): typeof this.qux {
    return 0 as never;
  }
  n(): (typeof this)['quux'] {
    return 0 as never;
  }
}
