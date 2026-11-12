declare function nothing(): void;
declare const u: undefined;
declare const maybe: void | undefined;

void nothing();
void (nothing());
void /* comment */ nothing();
void // line comment
  nothing();
void
  u;
void void nothing();
void(u);
(void u);
void (void 0);
const text = '🎉é'; void maybe;
const résumé = [void u, void (u), void/* é🎉 */u];
void (
  // inside the parentheses
  nothing()
);
void (((u)));
function wrapped(): void {
  return void nothing();
}
void [résumé, text, wrapped];
