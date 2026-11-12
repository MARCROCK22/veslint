// `return` without `;` before a line break other than LF (a lone CR, U+2028, U+2029 and CRLF,
// which this file has for real) returns nothing: the `any` after it is another statement.
declare const anyValue: any
function afterCr(): number | undefined {  return  anyValue}
function afterLs(): number | undefined {   return   anyValue }
function afterPs(): number | undefined {   return   anyValue }
function afterCrLf(): number | undefined {
  return
  anyValue
}
function sameLine(): number {  return anyValue }
function afterComment(): number {   return /* ab */ anyValue}
export { afterCr, afterLs, afterPs, afterCrLf, sameLine, afterComment }
