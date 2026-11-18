import { writable, derived } from 'svelte/store';

const a = writable(0);
export const b = derived(a, (x) => x);
export const c = derived([a], ([y]) => y);
