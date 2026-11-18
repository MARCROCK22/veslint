import { writable, derived } from 'svelte/store';

export const a = writable();
export const b = derived(a, ($a) => $a);
export const c = writable(1);
