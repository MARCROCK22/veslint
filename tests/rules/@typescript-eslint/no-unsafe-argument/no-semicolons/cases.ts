// Cases without `;`, with end-of-line comments, BOM, CRLF and emoji (columns in UTF-16).
declare const anyValue: any
declare function numberValue(n: number): void
declare function tagFn(parts: TemplateStringsArray, n: number): string
const party = '🎉🎉'; numberValue(anyValue) // after two emoji on the same line
numberValue((anyValue)) /* parentheses */
tagFn`a${anyValue}`
numberValue(...[anyValue] as [any])
void party
