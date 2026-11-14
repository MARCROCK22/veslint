declare function run(fn: () => unknown): void;
declare function makeSynchronous(fn: () => unknown): void;
declare let external: number;
const outside = 1;

// Reported.
export function handlerOne(): unknown {
	return outside + new Map().size;
}
run(function () {
	return outside;
});
/* @pure */
export function pure(): number {
	return outside;
}
export const arrow = (): Set<number> => {
	Set = Set;
	return new Set();
};

// Not reported.
export function other(): number {
	external = 2;
	return 1;
}
makeSynchronous(function () {
	return outside;
});
