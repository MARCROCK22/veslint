declare const pairs: [string, number][];
declare function fromPairs(value: unknown): unknown;
declare const utils: {object: {fromPairs: (value: unknown) => unknown}};
declare const _: {fromPairs: (value: unknown) => unknown};

fromPairs(pairs);
utils.object.fromPairs(pairs);
utils.object?.fromPairs(pairs);
utils['object'].fromPairs(pairs);
_.fromPairs(pairs);

class Holder {
	toObject(value: unknown) {
		return value;
	}

	run() {
		return this.toObject(pairs);
	}
}

export {Holder};
