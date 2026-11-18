// An import of a component resolves to the `*.svelte` module of env.d.ts, not to its virtual code,
// as in ESLint.
import Runes from './runes.svelte';

export const component = Runes;
