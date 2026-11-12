// array-type with CRLF line breaks: the fixes keep the text between the parts they replace.
let a: Array<
  string
> = [];
let b: readonly (
  string | number
)[] = [];
let c: ReadonlyArray<
  string | number
> = [];
let d: Readonly<
  string[]
> = [];
export { a, b, c, d };
