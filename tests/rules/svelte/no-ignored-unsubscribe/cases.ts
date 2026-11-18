declare const store: { subscribe(fn: () => void): () => void };
store.subscribe(() => {});
export const unsubscribe = store.subscribe(() => {});
