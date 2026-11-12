// Optional calls (`f?.()`): the `?.` belongs to the call, not to a member access.
declare const maybeTask: (() => Promise<number>) | undefined;
declare const holder: { run?: () => Promise<number>; go: () => Promise<number> } | undefined;
declare function handler(): void;
declare const cond: boolean;
async function optionalCalls() {
  maybeTask?.();
  holder?.run?.();
  holder?.go();
  holder?.go?.();
  (maybeTask?.());
  maybeTask?.().catch(handler);
  maybeTask?.().then(() => {});
  maybeTask?.().then(() => {}, handler);
  maybeTask?.().finally(() => {});
  (maybeTask?.())?.finally(() => {});
  cond && maybeTask?.();
  cond ? maybeTask?.() : null;
  void maybeTask?.();
  await maybeTask?.();
  holder?.run?.().catch(handler);
  holder?.['go']?.();
  holder?.['go']?.().catch(handler);
}

// An optional call inside a larger expression is a ChainExpression too: it is not looked at as a
// `.catch` or a `.then`.
declare const chained: Promise<number>;
async function sequences() {
  (1, chained.catch?.(() => {}));
  (1, chained.catch(() => {}));
  true ? chained.then?.(() => {}, () => {}) : 0;
}
export { sequences };
