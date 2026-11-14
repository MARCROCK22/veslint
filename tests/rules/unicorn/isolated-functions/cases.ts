declare function makeSynchronous<T>(fn: T): T;
declare function workerize<T>(fn: T): T;
declare const browser: { execute(fn: () => unknown): void; scripting: { executeScript(options: object): void } };
declare const page: { evaluate(fn: () => unknown): void };
declare const chrome: { scripting: { executeScript(options: object): void } };
type Shape = { a: number };

const outside = 1;
let counter = 0;

// Reported.
makeSynchronous(() => outside);
workerize(function (value: number) {
	return value + outside;
});
browser.execute(() => outside);
page.evaluate(() => outside);
chrome.scripting.executeScript({ func: () => outside });
browser.scripting.executeScript({ 'func': () => outside });

/** @isolated */
function isolated(): number {
	counter++;
	return outside;
}

// @isolated - works on arrow functions too
const arrow = (): number => outside;

const object = {
	/* @isolated */
	method(): number {
		return outside;
	},
};

class Base {
	value = 1;
}
class Child extends Base {
	/** @isolated */
	method(): number {
		return this.value + super.toString().length;
	}
}

makeSynchronous(() => {
	Array = [] as unknown as ArrayConstructor;
	return new Map();
});

makeSynchronous(function named(): number {
	return typeof named === 'function' ? 1 : 0;
});

// Not reported.
makeSynchronous((input: Shape): Shape => {
	const local = input.a;
	const nested = () => local;
	return { a: nested() + Math.max(1, 2) };
});
makeSynchronous(() => {
	function inner(this: unknown): unknown {
		return this;
	}
	return inner;
});
somethingElse(() => outside);
/* @isolated-not */
function notIsolated(): number {
	return outside;
}
declare function somethingElse(fn: () => unknown): void;

export { isolated, arrow, object, Child, notIsolated };
