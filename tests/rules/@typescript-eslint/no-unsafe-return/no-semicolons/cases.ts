// Cases without `;`, with end-of-line comments, BOM, CRLF and emoji (columns in UTF-16).
declare const anyValue: any
const party = '🎉🎉'; function f1() { return anyValue } // after two emoji on the same line
const f2 = () => anyValue // arrow
function f3(): Set<string> { return new Set<any>() } /* block comment */
const f4 = async () => Promise.resolve(anyValue) as Promise<any>
void [party, f1, f2, f3, f4]
