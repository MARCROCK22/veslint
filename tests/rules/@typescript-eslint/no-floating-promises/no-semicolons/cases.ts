// Cases without `;`, with end-of-line comments, BOM, CRLF and emoji (columns in UTF-16).
declare function task(): Promise<number>
declare const cond: boolean
task() // line comment
task() /* block comment */
const party = '🎉🎉'; task() // after two emoji on the same line
cond && task() // logical
cond ? task() : 1 // conditional
void party
