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
// typescript-eslint 8.72: a nullable boolean the fix keeps as it is (not negated) gets `?? false`,
// but not in the test of a condition (isConditionalTest).
declare const other: boolean;
const r1 = nb === true;
const r2 = !(nb !== true);
const r3 = !(nb === false);
const r4 = (nb === true) && other;
const r5 = other ? nb === true : false;
if (nb === true) {}
if (other && nb === true) {}
if (!(nb !== true)) {}
while (other || nb === true) {}
do {} while (nb == true);
for (; nb === true; ) {}
for (; (0, nb === true); ) {}
const r6 = (other ? nb === true : other) ? 1 : 2;
const r7 = nb !== false;
const r8 = [nb === true];
export { r1, r2, r3, r4, r5, r6, r7, r8 };
