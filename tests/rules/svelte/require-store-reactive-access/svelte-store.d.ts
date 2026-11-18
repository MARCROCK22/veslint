// The types of `svelte/store` and `svelte` the cases use (the package is not installed here).
declare module 'svelte/store' {
	export type Subscriber<T> = (value: T) => void;
	export type Unsubscriber = () => void;
	export interface Readable<T> {
		subscribe(this: void, run: Subscriber<T>, invalidate?: () => void): Unsubscriber;
	}
	export interface Writable<T> extends Readable<T> {
		set(this: void, value: T): void;
	}
	export function writable<T>(value?: T): Writable<T>;
	export function readable<T>(value?: T): Readable<T>;
	export function derived<S, T>(store: S, fn: (value: unknown) => T): Readable<T>;
}
declare module 'svelte' {
	export function getContext<T>(key: unknown): T;
}
