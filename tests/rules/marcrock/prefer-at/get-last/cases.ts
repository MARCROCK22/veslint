declare const array: number[];
declare const _: { last<T>(a: readonly T[]): T | undefined };
declare function getLast<T>(a: readonly T[]): T;
declare const utils: { lastOne<T>(a: readonly T[]): T };

_.last(getLast(utils.lastOne(array as number[][][])));
getLast(array);
utils.lastOne(array);
utils?.lastOne(array);
utils['lastOne'](array);
class K {
	last(a: number[]) {
		return a;
	}
	m() {
		return this.last(array);
	}
	static n() {
		return new.target;
	}
}
getLast(array, ...[]);
array[array.length - 1];
array[0];

export { K };
