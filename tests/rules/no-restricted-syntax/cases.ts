// Without options, nothing is restricted.
enum Color {
  Red,
}
const value = Math.random() ? Color.Red : 2;
export { value };
