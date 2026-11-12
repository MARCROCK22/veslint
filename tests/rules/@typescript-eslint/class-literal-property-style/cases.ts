// class-literal-property-style with 'fields' (the default): a getter whose first statement returns
// a literal (a Literal, a template or a tagged template without expressions) should be a readonly
// field, unless it overrides or a setter has the same static name; the suggestion writes the field
// with the accessibility and `static` of the getter.
declare function dec(...args: unknown[]): any;
declare const styled: any, gql: any, myValue: any, p1: any;
declare abstract class Base {
  get overridden(): string;
}
class Getters extends Base {
  get a() {
    return 'a';
  }
  get b() {
    return `b`;
  }
  get c() {
    return 1;
  }
  get d() {
    return 10n;
  }
  get e() {
    return null;
  }
  get f() {
    return true;
  }
  get g() {
    return /g/u;
  }
  get h() {
    return ('parenthesized');
  }
  get i() {
    return gql`query`;
  }
  get j() {
    return `j ${this.a}`;
  }
  get k() {
    return gql`k ${1}`;
  }
  get l() {
    return -1;
  }
  get m() {
    return undefined;
  }
  get n() {
    return 'first';
    return 'unreachable';
  }
  get o() {
    const x = 1;
    return 'o';
  }
  get p() {}
  get q(): string;
  get q() {
    return 'q';
  }
  public static get r() {
    return 'r';
  }
  protected get s() {
    return 's';
  }
  private static get t() {
    return 't';
  }
  get #u() {
    return 'u';
  }
  static get #v() {
    return 'v';
  }
  get [myValue]() {
    return 'computed';
  }
  get [/* before */ p1 /* after */]() {
    return 'commented';
  }
  get ['str']() {
    return 'str';
  }
  get 'quoted'() {
    return 'quoted';
  }
  get 42() {
    return 42;
  }
  @dec get decorated() {
    return 'decorated';
  }
  override get overridden() {
    return 'overridden';
  }
  get withSetter() {
    return 'x';
  }
  set withSetter(value) {}
  get computedSetter() {
    return 'x';
  }
  set ['computedSetter'](value) {}
  static set staticSetter(value) {}
  get staticSetter() {
    return 'x';
  }
  get privateNamed() {
    return 'x';
  }
  set #privateNamed(value) {}
  get [Symbol.iterator]() {
    return 'sym';
  }
  set [Symbol.iterator](value) {}
  get [Symbol.toStringTag]() {
    return 'tag';
  }
  get ''() {
    return 'empty';
  }
  set ''(value) {}
  get withComment() /* c */ {
    return 'c'; // trailing
  }
  get directive() {
    'use strict';
    return 'd';
  }
  method() {
    return 'not a getter';
  }
}
const objectGetter = {
  get a() {
    return 'an object';
  },
};
const Expression = class {
  get a() {
    return 'expression';
  }
};
abstract class Abstract {
  abstract get a(): string;
}
declare class Declared {
  get a(): string;
}
