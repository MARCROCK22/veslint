// Cases without `;`, with end-of-line comments, BOM, CRLF and emoji (columns in UTF-16).
declare const anyValue: any
const party = '🎉🎉'; anyValue.a // after two emoji on the same line
anyValue[party] /* block comment */
anyValue.b.c.d // in a chain only the first one counts
const k: any = 'x'
const o = { x: 1 }
o[k] // computed name
void party
