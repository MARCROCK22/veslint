declare module '$app/types' {
	export type Pathname = '/' | '/about';
	export type ResolvedPathname = `${'' | `/${string}`}${Pathname}`;
}
declare module '$app/paths' {
	import type { ResolvedPathname } from '$app/types';
	export function resolve(path: string): ResolvedPathname;
	export function asset(path: string): string;
}
declare module '$app/navigation' {
	export function goto(url: string | URL): Promise<void>;
	export function pushState(url: string | URL, state: unknown): void;
	export function replaceState(url: string | URL, state: unknown): void;
}
