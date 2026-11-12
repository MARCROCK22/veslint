// dot-notation with the default options.
declare const a: Record<string, { b: number; c: number }>;
declare const maybe: { foo?: { bar: number } } | undefined;

// Reported: string, template, keyword-named and escaped keys.
a['foo'];
a["foo"];
a[`foo`];
a['class'];
a['foo'];
a['$dollar'];
a['_under'];
a['foo']['b'];
a['foo'] = { b: 1, c: 2 };
a!['foo'];
maybe?.['foo']?.['bar'];
a[('foo')];
/* 😀 */ a['emoji'];

// Reported: boolean and null literal keys.
// @ts-expect-error -- `true` is not a valid index type.
a[true];
// @ts-expect-error -- `false` is not a valid index type.
a[false];
// @ts-expect-error -- `null` is not a valid index type.
a[null];

// Not reported: not valid identifiers, numbers, substitutions, other expressions.
a['foo bar'];
a['foo-bar'];
a['0'];
a['1x'];
a[''];
a['été'];
const index = 'foo';
a[index];
a[`${index}`];
a['foo' as string];
a.class;

// Not reported: indexed access types are not member expressions.
type Item = (typeof a)['foo'];
type Bar = NonNullable<typeof maybe>['foo'];

class Base {
  method(): number {
    return 1;
  }
}

class Derived extends Base {
  override method(): number {
    // Reported: `super` member.
    return super['method']();
  }
}

void (null as unknown as Item);
void (null as unknown as Bar);
void Derived;
