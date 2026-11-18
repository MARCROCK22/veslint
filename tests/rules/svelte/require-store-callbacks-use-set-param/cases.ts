import { readable } from 'svelte/store';

export const a = readable(0, () => {});
export const b = readable(0, (s) => s(1));
