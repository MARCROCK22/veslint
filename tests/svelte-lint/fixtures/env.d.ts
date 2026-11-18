// What the fixtures need of Svelte, without its package: the `*.svelte` module other files import a
// component through, and what the virtual code svelte-eslint-parser gives typescript-eslint names
// (`import('svelte')`, `import('svelte/elements')`) and the stores.
declare module '*.svelte' {
  import type { Component } from 'svelte';
  const component: Component<Record<string, unknown>>;
  export default component;
}

declare module 'svelte' {
  export interface Component<Props = Record<string, never>, Exports = Record<string, never>> {
    (internals: unknown, props: Props): Exports;
  }
  export class SvelteComponent<Props = Record<string, unknown>, Events = Record<string, unknown>, Slots = Record<string, unknown>> {
    $$prop_def: Props;
    $$events_def: Events;
    $$slot_def: Slots;
  }
  export type ComponentProps<T> = T extends Component<infer P> ? P : never;
  export type ComponentEvents<T> = T extends SvelteComponent<unknown, infer E> ? E : never;
  export interface Snippet<Parameters extends unknown[] = []> {
    (...args: Parameters): { '{@render ...} must be called with a Snippet': string };
  }
}

declare module 'svelte/elements' {
  export interface SvelteHTMLElements {
    [name: string]: { [attribute: string]: unknown };
  }
}

declare module 'svelte/store' {
  export interface Writable<T> {
    subscribe(run: (value: T) => void): () => void;
    set(value: T): void;
    update(updater: (value: T) => T): void;
  }
  export function writable<T>(value: T): Writable<T>;
}
