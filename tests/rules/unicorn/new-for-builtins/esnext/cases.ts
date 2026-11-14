// unicorn/new-for-builtins with the esnext lib: Temporal and the disposable stacks.
const t1 = Temporal.PlainDate(2020, 1, 1);
// @ts-expect-error -- not callable
const t2 = Temporal.Now();
// @ts-expect-error -- not a constructor
const t3 = new Temporal.Now();
const t4 = DisposableStack();
const t5 = AsyncDisposableStack();
const t6 = SuppressedError(1, 2);
