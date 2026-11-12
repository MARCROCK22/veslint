declare const b: boolean;
declare const nb: boolean | undefined;
declare const nn: boolean | null;
declare const obj: { maybe?: boolean; fn(): boolean | null };
declare const maybeObj: { flag: boolean } | undefined;

if (nb === true) {
}
if (nb !== true) {
}
if (nb === false) {
}
if (nb !== false) {
}
if (true === nb) {
}
if (false === nb) {
}
if (!(nb === true)) {
}
if (!(nb === false)) {
}
if (!(nb !== false)) {
}
if (!(nb !== true)) {
}
const y1 = nb !== false ? 1 : 2;
const y2 = nb !== false && b;
const y3 = nb === false && b;
const y4 = (nb !== false).toString();
const y5 = [nb !== false, nb === false, nn === false];
if (obj.maybe === false) {
}
if (obj.fn() !== false) {
}
if (maybeObj?.flag === false) {
}
if (maybeObj?.flag !== false) {
}
if (maybeObj?.flag === true) {
}
if ((nb ?? undefined) === true) {
}
if ((nb ?? undefined) === false) {
}
if ((nb ?? undefined) !== false) {
}
if ((nb as boolean | undefined) !== false) {
}
const y6 = !(nb !== false) ? 1 : 2;
const y7 = typeof (nb !== false);
const y8 = (nn) /* c */ !== /* d */ false;
void [y1, y2, y3, y4, y5, y6, y7, y8];
