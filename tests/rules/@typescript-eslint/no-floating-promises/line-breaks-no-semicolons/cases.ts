// Statements without `;` that end at a line break other than LF: a lone CR, U+2028, U+2029 and
// CRLF, which this file has for real. The scanner of the grammar only gave the automatic
// semicolon at a LF.
declare function task(): Promise<number>
declare function tag(strings: TemplateStringsArray): Promise<void>
declare function in_range(n: number): Promise<void>
declare function index(n: number): Promise<void>
declare let count: number
// After a call, at each line break.
task()task() task() task()
task()
// After a line comment and after a block comment.
task() // atask() /* b */ task() // c task()
// A block comment with a line break in it is one too.
task() /* ab */ task() /* c d */ task() /* e f */ task()
// `return` and `++` at the start of a line, and what continues a statement.
async function inside(): Promise<void> {  task()   count   ++count  return  task() }
count = count  + 1 task()   .finally(() => {})tag`x` void inside
// After the block of an arrow function, and before a name that starts with `in`.
const made = async () => {}(async () => { await made() })() 
let total = 0 in_range(total)index(total)total = count in_range(total)
