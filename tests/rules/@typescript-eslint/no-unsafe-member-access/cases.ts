// Cases of no-unsafe-member-access (typescript-eslint 8.62.0, default options), with strict.
declare const anyValue: any;
declare const objectValue: { a: { b: number }; [k: string]: unknown };
declare const key: any;
declare let index: any;
declare const list: number[];

function cases() {
  anyValue.a;
  anyValue.a.b.c;
  anyValue['x'];
  anyValue[`x`];
  anyValue[1];
  objectValue[key];
  objectValue.a.b;
  anyValue?.a;
  anyValue?.[key];
  (anyValue as any).x;
  anyValue[key];
  list[index++];
  list[index];
  objectValue.a[key];
  missing.x;
  missing[key];
  anyValue.method().other;
  anyValue.a = 1;
  delete anyValue.a;
  const { a } = anyValue;
  return a;
}
void cases;

// In a type, `typeof a.b` is a qualified name, not a member access.
type OfType = typeof anyValue.a;
export type { OfType };
