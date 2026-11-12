export {};
declare const plain: { a: number };

// A local `String` in the scope of the call itself is not the builtin; one in an outer scope is
// not seen (typescript-eslint only looks at the innermost scope).
function local(): void {
  const String = (value: unknown): string => '';
  String(plain);
}
function outer(): void {
  function String(value: unknown): string {
    return '';
  }
  {
    String(plain);
  }
}
String(plain);
