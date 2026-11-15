declare function call(...args: unknown[]): void;
declare const items: number[];

const a = 1, b = 2;
const c = 1
	, d = 2;
const e = 1
	,
	f = 2;
const g = 1 /* block */
	,
	h = 2;
const i = 1
	, /* block */
	j = 2;
const k = 1
	, // line
	l = 2;

const array = [
	1,
	2
	, 3,
];
const holes = [, , 1];
const leading = [
	,
	1,
];
const consecutive = [
	1,
	,
	2,
];
const allHoles = [
	,
	,
];

const object = {
	a: 1
	, b: 2,
};

const { m
	, n } = { m: 1, n: 2 };
const [o
	, p] = items;

function params(x: number
	, y: number) {
	return x + y;
}

const arrow = (x: number
	, y: number) => x + y;

const fnExpression = function (x: number
	, y: number) {
	return x;
};

call(1
	, 2);
call((1)
	, (2));
new Map([[1, 2]]
	, );

import { readFile
	, writeFile } from 'node:fs';
export { readFile
	, writeFile };
import data from './data.json' with { type: 'json'
	, other: 'x' };
export * from './data.json' with { type: 'json'
	, other: 'x' };

const lazy = import('./data.json'
	, { with: { type: 'json' } });

let seq = 0;
seq = (1
	, 2);

interface First {}
interface Second {}
class Impl implements First
	, Second {}
const ImplExpression = class implements First
	, Second {};

declare function declared(x: number
	, y: number): void;
type Fn = (x: number
	, y: number) => void;
type Ctor = new (x: number
	, y: number) => object;
abstract class Base {
	abstract method(x: number
		, y: number): void;
}
type Generic<A
	, B> = [A, B];
type Inst = Generic<1
	, 2>;

enum Enum {
	A
	, B,
}

type Literal = {
	a: string
	, b: string,
	new (x: number
		, y: number): object;
	(x: number
		, y: number): void;
	method(x: number
		, y: number): void;
};

type Index = {
	[key: string
	]: string;
};

interface Extended extends First
	, Second {
	a: string
	, b: string;
}

type Tuple = [string
	, number];

const one = 1, two = 2,
	three = 3;
call(one
	,two,three);
