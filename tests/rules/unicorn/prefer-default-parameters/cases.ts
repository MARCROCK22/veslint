declare function use(...values: unknown[]): void;
declare const options: {name?: string; count?: number; flag?: boolean};
declare const pairs: [string?, number?][];

// Reassignment
export function reassign(value?: number) {
	value = value || 1;
	return value;
}
export function nullish(value?: string) {
	value ??= 'fallback';
	return value;
}
export function logicalOr(value?: string | number) {
	value ||= 'fallback';
	return value;
}
export const arrow = (value?: number) => {
	value = value ?? 2;
	return value;
};
export const bare = value => {
	value = value ?? 2;
	return value;
};
export const bareJs = function (value) {
	value = value || -1;
	return value;
};
export function commented(value?: number) {
	value = value ?? /* keep */ 1;
	return value;
}
export function sameLine(value?: number) { value ??= 1; return value; }
export function noSpace(value?: number) {value ??= 1;return value;}
export function earlier(fallback: number, value?: number) {
	value ??= fallback;
	return value;
}
export function semicolon(value?: number) {
	use(1)
	value ??= 1
	;[value].forEach(use)
}

export function semicolonNeeded(value?: number) {
	const list = [1]
	value ??= 1
	;[value, list].forEach(use)
}
export function ownLine(value?: number) {
	const list = [1];
	  value ??= 1;  
	return [value, list];
}

// Not reported
export function sideEffect(value?: number) {
	use(value);
	value ??= 1;
	return value;
}
export function strict(value?: number) {
	'use strict';
	value ??= 1;
	return value;
}
export function notLast(value?: number, other?: number) {
	value ??= 1;
	return value + (other ?? 0);
}
export function nonStatic(value?: number) {
	value ??= Date.now();
	return value;
}
export function different(value?: number, other?: number) {
	value = other ?? 1;
	return value;
}
export class Setter {
	set value(value: number | undefined) {
		value ??= 1;
		use(value);
	}
}
export function inner(value?: number) {
	if (value) {
		value ??= 1;
	}
	return value;
}
export function incompatible(value?: string | null): string {
	value ??= 'x';
	return value;
}

// Fallback reads
export const read = (value?: number) => value ?? 1;
export const readTwice = (value?: number) => [value ?? 1, value ?? 1];
export const readOr = (value?: 1 | 2) => value || 1;
export const readBare = value => value ?? 'x';
export const readNegative = (value?: number) => value ?? -1;
export const readBigint = (value?: bigint) => value ?? -1n;
export const readTemplate = (value?: string) => value ?? `text`;
export function readEarlier(fallback: string, value?: string) {
	return value ?? fallback;
}
export function readCommented(value?: number) {
	return value ?? /* keep */ 1;
}
export const {name: readName} = options;
use(readName ?? 'name');
const {count} = options;
use(count ?? 0);
const [first] = pairs[0] ?? [];
use(first ?? 'first');
for (const [key, size] of pairs) {
	use(key ?? 'key', size ?? 0);
}
export function readObject({name}: {name?: string}) {
	return name ?? 'name';
}

// Fallback reads not reported
export const readDifferent = (value?: number) => [value ?? 1, value ?? 2];
export const readMixed = (value?: number) => [value ?? 1, value || 1];
export const readUsed = (value?: number) => [value ?? 1, value];
export const readRegex = (value?: RegExp) => value ?? /x/;
export const readFalsy = (value?: number) => value || 1;
export const readString = (value?: string) => value || 'x';
export const readBoolean = (value?: boolean) => value || true;
export const readTemplateType = (value?: `${string}`) => value || 'x';
export const readEmptyLiteral = (value?: '' | 'a') => value || 'a';
export const readZeroLiteral = (value?: 0 | 1) => value || 1;
export const readNull = (value?: string | null) => value ?? 'x';
export const readUnknown = (value?: unknown) => value ?? 'x';
export const readAny = (value?: any) => value ?? 'x';
export const readGeneric = <T extends string>(fallback: T, value?: T) => value ?? fallback;
export const readNarrowed = (value?: 'a' | 'b'): 'a' => value ?? 'a';
var legacy = options.name;
use(legacy ?? 'legacy');
export const exported = options.flag;
use(exported ?? false);
export function readSetter() {
	return {
		set value(value: number | undefined) {
			use(value ?? 1);
		},
	};
}
export function readDefault({name = 'a'}: {name?: string}) {
	return name ?? 'b';
}
export function readRest(...rest: number[]) {
	return rest ?? [];
}
export const readLater = (value?: string, fallback = 'x') => value ?? fallback;
