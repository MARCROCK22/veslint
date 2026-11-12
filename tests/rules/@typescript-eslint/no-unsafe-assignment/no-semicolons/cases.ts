// Cases without `;`, with end-of-line comments, BOM, CRLF and emoji (columns in UTF-16).
declare const anyValue: any
declare const list: any[]
const party = '🎉🎉'; const a = anyValue // after two emoji on the same line
const [b] = list // array of any
class K {
  field = anyValue // field without a semicolon
  other: Set<string> = new Set<any>()
}
const o = { key: anyValue, ...{} }
const arr = [...list] /* block comment */
void [party, a, b, K, o, arr]
