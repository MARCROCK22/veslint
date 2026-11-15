declare function call(fn: (value: number) => unknown): void;
call(a => a);
call((a) => a);
call(async a => a);
call(async (a) => a);
call(async(a) => a);
call((a): number => a);
call((a: number) => a);
call((a?) => a);
call(a => { return a; });
call((a) => { return a; });
call((/* comment */ a) => a);
call((a /* comment */) => a);
call(<T,>(a: T) => a);
call(([a]) => a);
call(({ a }: { a: number }) => a);
call((a = 1) => a);
call((...a) => a);
call(() => 1);
call((a, b) => a + b);
export const typed = <T>(a: T) => a;
export const nested = (a) => (b) => a + b;
call(( a ) => a);
call((
  a
) => a);
call((a) =>
  a);
