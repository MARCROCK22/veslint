/** @deprecated By name. */
function allowedByName(): void {}
/** @deprecated Not allowed. */
function notAllowed(): void {}
allowedByName();
notAllowed();

interface Holder {
  /** @deprecated Held. */
  held: number;
}
interface Other {
  /** @deprecated Other. */
  held: number;
}
declare const holder: Holder;
declare const other: Other;
void holder['held'];
void other['held'];
void holder.held;
void other.held;
/** @deprecated A holder. */
declare const deprecatedHolder: Holder;
void deprecatedHolder;

void 'abc'.substr(1);
void escape('a');

declare const win: Window & typeof globalThis;
/** @deprecated A window. */
declare const deprecatedWindow: Window;
void deprecatedWindow;
void win;
