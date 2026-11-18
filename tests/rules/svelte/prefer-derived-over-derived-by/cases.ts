declare const $derived: { by<T>(f: () => T): T };
export const a = $derived.by(() => 1);
