declare const b: boolean;
declare const obj: { flag: boolean; fn(): boolean; list: boolean[] };
declare function call(): boolean;
declare function tag(strings: TemplateStringsArray): boolean;

if (b === true) {
}
if (b !== true) {
}
if (b === false) {
}
if (b !== false) {
}
if (true === b) {
}
if (false !== b) {
}
if (!(b === true)) {
}
if (!(b !== false)) {
}
if (!(b === false)) {
}
if (!(b !== true)) {
}
if ((b) === true) {
}
if ((b === true)) {
}
if ((b && b) === true) {
}
if ((b && b) === false) {
}
if ((b && b) !== true) {
}
if (!((b || b) === false)) {
}
if (obj.flag === true) {
}
if (obj['flag'] !== true) {
}
if (call() === false) {
}
if (obj.fn() !== true) {
}
if (tag`x` === false) {
}
if (new Boolean(b).valueOf() === false) {
}
if ((b as boolean) === true) {
}
if ((b as boolean) === false) {
}
if (b! === false) {
}
if (!b === false) {
}
if ((b ? b : !b) !== false) {
}
const x1 = b === true ? 1 : 2;
const x2 = (b && b) === true ? 1 : 2;
const x3 = !!(b === true);
const x4 = typeof (b === false);
const x5 = (b === true).toString();
const x6 = ((b && b) === true).toString();
const x7 = [b === true, b === false];
const x8 = (b && b) === true && b;
const x9 = (b as boolean) === true || b;
const x10 = void ((b, b) === true);
async function f() {
  return [await ((b && b) === true), await (b === true)];
}
const x11 = b /* left */ === /* right */ true;
const x12 = (b satisfies boolean) === true ? 1 : 2;
const résumé = '🎉é'; const x13 = b === true;
const x14 =
  obj.list[0] ===
  false;
void [x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, f, résumé];
