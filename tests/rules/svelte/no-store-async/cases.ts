import { writable, readable } from 'svelte/store';

export const a = writable(0, async () => {});
export const b = readable(null, async (set) => {
  set(null);
});
export const c = writable(0, () => {});
