export function outer(value: number): number {
	// Reported.
	function inner(a: number): number {
		return a * 2;
	}
	// Not reported: an arrow function.
	const arrow = (b: number): number => b + 1;
	return inner(value) + arrow(value);
}
