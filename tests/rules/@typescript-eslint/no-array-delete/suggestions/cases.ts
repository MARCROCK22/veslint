// The `useSplice` suggestion: parentheses, sequences, comments inside the expression and the
// indentation of the line.
declare const array: number[];
declare const key: number;
delete array[(key)];
delete array[(key, 1)];
delete (array)[0];
delete /* before */ array[/* inside */ 0];
  delete array[0]; // trailing, outside the expression
function indent() {
    delete array // line comment
      [key];
}
delete (array as number[])[0];
delete array![0];
const emoji = '😀'; delete array[0 /* 😀 */];
delete array[key + 1] /* after, outside */;
export { indent, emoji };
