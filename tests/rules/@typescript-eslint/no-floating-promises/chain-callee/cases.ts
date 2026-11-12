// The callee of `.catch(…)`, `.then(…, …)` and `.finally(…)` must be a member access. An optional
// chain in parentheses is a ChainExpression for ESTree, so `(p?.catch)(handler)` is not a handled
// promise for the rule: it reports the statement, whatever the handler.
declare const promise: Promise<number>;
declare const maybe: Promise<number> | undefined;
declare function handler(e: unknown): void;

// Reported: the chain ends at the parentheses.
(promise?.catch)(handler);
(maybe?.catch)(handler);
(promise?.then)(handler, handler);
(promise?.['catch'])(handler);
(promise?.finally)(handler);
(promise?.then(handler).catch)(handler);

// Not reported: a member access, with or without parentheses, and an optional call of one.
promise?.catch(handler);
(promise.catch)(handler);
((promise.catch))(handler);
promise.catch?.(handler);
(promise.then)(handler, handler);
maybe?.then(handler, handler);
