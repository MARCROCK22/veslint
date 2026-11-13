// Reported by the selectors of options.json.
enum Color {
  Red,
  Green,
}
const legacy = <string>(Color.Red as unknown);
function call(): void {
  eval('1');
}
const value = Math.random() ? 1 : 2;
// Not reported.
const fine = Color.Green;
function other(): void {
  call();
}
export { legacy, value, fine, other };
