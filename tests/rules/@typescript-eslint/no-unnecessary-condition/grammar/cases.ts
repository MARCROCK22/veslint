// A comparison with a parenthesized signed number is a binary expression, not type arguments.
declare const two: 2;
declare const n: number;
if (two < (-2)) {
}
if (two > (+3)) {
}
const less = n < (-2);
export { less };
