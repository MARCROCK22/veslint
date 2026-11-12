import { createMiddleware } from 'seyfert';
import * as Seyfert from 'seyfert';
import { createMiddleware as middleware } from 'seyfert';

declare const flag: boolean;
declare const kind: number;
declare const xs: number[];
declare let maybe: string | undefined;
declare const obj: { method(value: unknown): void } | undefined;
declare function work(): Promise<void>;
declare function risky(): void;
declare function noop(): void;
declare function log(): void;
declare function next(): void;
declare const deep: { inner: { method(value: unknown): void } } | undefined;
declare const list: unknown[] | undefined;
declare const call: ((value: unknown) => void) | undefined;
declare const empty: '';
declare const nothing: null;
declare const absent: undefined;
declare const empty2: void;
declare const zero: 0n;
declare const ten: 10n;
declare const object: object;
declare const symbol: symbol;
declare const unique: unique symbol;
declare const one: 1 | 2;
declare const no: false;
declare const mixed: '' | 'x';
declare const text: string;
enum Level {
  Off,
  On,
}
declare const off: Level.Off;
declare const on: Level.On;

// Valid: next() or stop() on every path that returns.
export const v1 = createMiddleware<void>(({ next }) => { next(); });
export const v2 = createMiddleware<void>(({ next }) => next());
export const v3 = createMiddleware<void>(({ next }) => void next());
export const v4 = createMiddleware<void>(({ stop }) => stop('no'));
export const v5 = createMiddleware<void>(async ({ next }) => { await work(); next(); });
export const v6 = createMiddleware<void>(function ({ next }) { next(); });
export const v7 = createMiddleware<void>(async function named({ next }) { await next(); });
export const v8 = createMiddleware<void>(middle => middle.next());
export const v9 = createMiddleware<void>(middle => { middle.stop('no'); });
export const v10 = createMiddleware<void>(({ next: go }) => { go(); });
export const v11 = createMiddleware<void>(({ next = noop }) => { next(); });
export const v12 = createMiddleware<void>(({ next, ...rest }) => { next(); return rest; });
export const v13 = createMiddleware<void>(({ next, stop }) => (flag ? next() : stop('no')));
export const v14 = createMiddleware<void>(({ next, stop }) => { if (flag) next(); else if (kind) stop('no'); else next(); });
export const v15 = createMiddleware<void>(({ next, stop }) => {
  switch (kind) {
    case 1:
      return next();
    case 2:
      stop('two');
      break;
    default:
      next();
  }
});
export const v16 = createMiddleware<void>(({ next }) => { try { if (flag) return; } finally { next(); } });
export const v17 = createMiddleware<void>(({ next }) => { while (true) { next(); break; } });
export const v18 = createMiddleware<void>(({ next }) => { for (;;) { if (flag) { next(); return; } } });
export const v19 = createMiddleware<void>(({ next }) => { if (!flag) throw new Error('no'); next(); });
export const v20 = createMiddleware<void>(({ next }) => { block: { if (flag) break block; next(); return; } next(); });
export const v21 = createMiddleware<void>(({ next }) => { next?.(); });
export const v22 = createMiddleware<void>(({ next }) => (log(), next()));
export const v23 = createMiddleware<void>(({ next }) => { return void next(); });
export const v24 = createMiddleware<void>(({ next, stop }) => { try { risky(); next(); } catch { stop('failed'); } });
export const v25 = createMiddleware<void>(({ next }) => { const inner = createMiddleware<void>(({ next: again }) => again()); next(); return inner; });
export const v26 = Seyfert.createMiddleware<void>(({ next }) => { do { log(); } while (flag); next(); });
// A condition whose type is always truthy or always falsy picks its branch.
export const v27 = createMiddleware<void>(({ next }) => { if (true) next(); });
export const v28 = createMiddleware<void>(({ next }) => { if (1) next(); });
export const v29 = createMiddleware<void>(({ next }) => { if (empty) { log(); } else next(); });
export const v30 = createMiddleware<void>(({ next }) => { if (nothing) log(); else { next(); } });
export const v31 = createMiddleware<void>(({ next }) => { if (zero) log(); else next(); });
export const v32 = createMiddleware<void>(({ next }) => { if (object) { next(); } });
export const v33 = createMiddleware<void>(({ next }) => { if (symbol) next(); });
export const v36 = createMiddleware<void>(({ next }) => { if (unique) next(); });
export const v37 = createMiddleware<void>(({ next }) => { if (absent) log(); else next(); });
// @ts-expect-error: TypeScript does not test `void` for truthiness
export const v38 = createMiddleware<void>(({ next }) => { if (empty2) log(); else next(); });
export const v39 = createMiddleware<void>(({ next }) => { if (ten) next(); });
export const v40 = createMiddleware<void>(({ next }) => { if (one) next(); });
export const v41 = createMiddleware<void>(({ next }) => { if (no) log(); else next(); });
export const v42 = createMiddleware<void>(({ next }) => { if (off) log(); else next(); });
export const v43 = createMiddleware<void>(({ next }) => { if (on) next(); });
const yes = true as const;
export const v34 = createMiddleware<void>(({ next }) => { if (yes) { const a = 1; log(); next(); } });
export const v35 = createMiddleware<void>(({ next }) => { if (absent) {} else if (kind) next(); else throw new Error('no'); });

// Reported where the function starts: a path returns without next() or stop().
export const i1 = createMiddleware<void>(({ next }) => {});
export const i2 = createMiddleware<void>(({ next }) => { if (flag) next(); });
export const i3 = createMiddleware<void>(({ next }) => flag && next());
export const i4 = createMiddleware<void>(({ next }) => flag || next());
export const i5 = createMiddleware<void>(({ next }) => maybe ?? next());
export const i6 = createMiddleware<void>(({ next }) => { flag ? next() : undefined; });
export const i7 = createMiddleware<void>(({ next }) => { setTimeout(() => next(), 0); });
export const i8 = createMiddleware<void>(({ next }) => { for (const _ of xs) next(); });
export const i9 = createMiddleware<void>(({ next }) => { while (flag) next(); });
export const i10 = createMiddleware<void>(({ next }) => { switch (kind) { case 1: next(); break; } });
export const i11 = createMiddleware<void>(({ next }) => { switch (kind) { case 1: next(); break; default: } });
export const i12 = createMiddleware<void>(async ({ next }) => { try { await work(); next(); } catch {} });
export const i13 = createMiddleware<void>(({ next }) => { try { risky(); } catch { return; } next(); });
export const i14 = createMiddleware<void>(({ next: go }) => { next(); });
export const i15 = createMiddleware<void>(middle => { middle['next'](); });
export const i16 = createMiddleware<void>(middle => { const { next } = middle; next(); });
export const i17 = createMiddleware<void>((...args) => { args[0].next(); });
export const i18 = createMiddleware<void>(({ next }) => { (flag ? next : noop)(); });
export const i19 = createMiddleware<void>(({ next }) => { do { if (flag) continue; next(); } while (false); });
export const i20 = createMiddleware<void>(({ next }) => { outer: for (;;) { if (flag) break outer; next(); return; } });
export const i21 = createMiddleware<void>(({ next }) => { if (true) {} else next(); });
export const i22 = createMiddleware<void>(({ next }) => { if (flag as boolean) next(); });
export const i23 = createMiddleware<void>(function ({ next }) { if (flag) next(); });
export const i24 = createMiddleware<void>(async function ({ next }) {});
export const i25 = Seyfert.createMiddleware<void>(({ next }) => {});
export const i26 = createMiddleware<void>(({ next }) => { return; next(); });
export const i27 = createMiddleware<void>(({ next, stop }) => { if (flag) { stop('no'); } else if (kind) { next(); } });
export const i28 = createMiddleware<void>(({ next }) => { maybe ??= (next(), 'x'); });
export const i29 = createMiddleware<void>(({ next }) => { obj?.method(next()); });
export const i30 = createMiddleware<void>(function* ({ next }) { if (flag) yield next(); });
export const i31 = /* 😀 ñ */ createMiddleware<void>(({ next }) => {});
export const i32 = createMiddleware<void>(
  // a comment before the function
  async ({ next }) => {
    if (flag) next();
  },
);
export const i33 = createMiddleware<void>((({ next }) => {}));
export const i34 = createMiddleware<void>(({ next }) => { if (kind) {} else if (flag) next(); else next(); });
// The type of the condition does not say: both branches must advance.
export const i35 = createMiddleware<void>(({ next }) => { if (mixed) next(); });
export const i36 = createMiddleware<void>(({ next }) => { if (text) next(); });
// After a `?.`, the rest of the chain, the arguments of its calls too, may not run.
export const i37 = createMiddleware<void>(({ next }) => { deep?.inner.method(next()); });
export const i38 = createMiddleware<void>(({ next }) => { void list?.[(next(), 0)]; });
export const i39 = createMiddleware<void>(({ next }) => { call?.(next()); });
export const i40 = createMiddleware<void>(({ next }) => { deep?.inner!.method(next()); });
// Parentheses end the chain: what comes after them runs.
export const v44 = createMiddleware<void>(({ next }) => { (deep?.inner)!.method(next()); });
export const v45 = createMiddleware<void>(middle => { middle?.next(); });

// Not a middleware of seyfert's createMiddleware: never reported.
export const n1 = middleware<void>(({ next }) => {});
const handler = ({ next }: { next: () => void }) => {};
export const n2 = createMiddleware<void>(handler);
export const n3 = createMiddleware<void>((({ next }) => {}) as Parameters<typeof createMiddleware<void>>[0]);
function local(callback: (args: { next(): void }) => void) {
  return callback;
}
export const n4 = local(({ next }) => {});
