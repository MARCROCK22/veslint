// Cases without `;`, with end-of-line comments, BOM, CRLF and emoji (columns in UTF-16).
declare const anyValue: any
const party = '🎉🎉'; anyValue() // after two emoji on the same line
anyValue.method() // line comment
new anyValue() /* block comment */
anyValue`template ${party}`
const f = anyValue
;(f)()
void party
