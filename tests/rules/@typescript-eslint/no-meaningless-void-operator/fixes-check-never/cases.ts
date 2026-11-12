declare function fail(): never;
declare function nothing(): void;
declare const n: never;
declare const voidOrNever: void | never;
declare function either(): undefined | never;

void fail();
void (fail());
void /* comment */ n;
void
  n;
const text = '🎉é'; void n;
void void fail();
void nothing();
void voidOrNever;
void either();
void (n as never);
void [text];
