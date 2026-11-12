// A tagged template with type arguments.
declare function tagged<T>(strings: TemplateStringsArray): Promise<T>;
async function templates() {
  tagged<string>`x`;
  tagged`y`;
}
export { templates };

// After the block of an arrow function, a line that starts with `(` or `[` is another statement.
const first = async () => {}
(async () => { await first() })()
const second = async () => {}
[first(), second()]
class WithFields {
  field = async () => {}
  ['computed']() { first() }
}
export { first, second, WithFields }

// A call with type arguments that could be read as two comparisons: its type argument is a
// function type that returns an object type, or has type arguments itself.
declare function generic<T>(value?: unknown): Promise<T>;
generic<() => { value: { n: number } }>(1);
generic<Array<number> | null>(null);
// Type arguments without a call before a line break are an instantiation expression, and the
// next line is another statement.
const instantiated = generic<number>
generic<string>()
const compared = first < second > generic
export { instantiated, compared };

// A comment with a line break ends a statement, a `return` and a `yield`.
declare let counter: number;
function commented() {
  return /* not
  returned */ generic<number>();
}
function* yielded() {
  yield /* not
  yielded */ generic<number>();
}
counter = 1 /* the next
statement */ generic<number>()
export { commented, yielded };
