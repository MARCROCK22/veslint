import { SvelteSet } from 'svelte/reactivity';
declare function $state<T>(v: T): T;
export const a = $state(new SvelteSet());
