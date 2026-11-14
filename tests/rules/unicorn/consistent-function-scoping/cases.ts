declare function useEffect(callback: () => void, deps: unknown[]): void;
declare const vi: { mock(path: string, factory: () => unknown): void; hoisted(factory: () => unknown): unknown };
declare const items: number[];

// Reported.
export function outer(value: number): number {
	function inner(a: number): number {
		return a * 2;
	}
	const arrow = (b: number): number => b + 1;
	const expression = function named(c: number): number {
		return c;
	};
	return inner(value) + arrow(value) + expression(value);
}

export function withLoop(): void {
	for (const item of items) {
		const log = (x: number): void => console.log(x);
		log(item);
	}
}

export class Service {
	method(): () => number {
		const helper = (): number => 1;
		return helper;
	}
}

export function generic<T>(value: T): T {
	function identity<U>(x: U): U {
		return x;
	}
	return identity(value);
}

// Not reported.
// The return type of `wait` refers to `Promise`, which the outer return type refers to too.
export async function asyncOuter(): Promise<void> {
	async function wait(): Promise<void> {}
	await wait();
}

export function usesOuter(value: number): number {
	function inner(): number {
		return value * 2;
	}
	const arrow = (): number => value;
	return inner() + arrow();
}

export function usesThis(this: { x: number }): () => number {
	const arrow = (): number => this.x;
	return arrow;
}

export function recursion(n: number): number {
	function fact(k: number): number {
		return k <= 1 ? 1 : k * fact(k - 1);
	}
	return fact(n) + n;
}

// `a` uses a neighbour, `b` does not (reported).
export function neighbours(): number {
	function a(): number {
		return b();
	}
	function b(): number {
		return 1;
	}
	return a();
}

export function hook(): void {
	useEffect(() => {
		const handler = (): void => {};
		handler();
	}, []);
}

vi.mock('module', () => {
	function create(): number {
		return 1;
	}
	return { create };
});

export function iife(): number {
	return (() => {
		const helper = (): number => 1;
		return helper();
	})();
}

export function loopUses(): void {
	for (const item of items) {
		const log = (): void => console.log(item);
		log();
	}
}

export function typeUse<T>(): (value: T) => T {
	const cast = (value: T): T => value;
	return cast;
}

export const topLevel = (): number => 1;
function topLevelFunction(): number {
	return 2;
}
void topLevelFunction;
