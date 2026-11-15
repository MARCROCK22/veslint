'use strict';
"use strict";
declare function tag(strings: TemplateStringsArray, ...values: unknown[]): string;
declare const value: number;

const a = 'single';
const b = "double";
const c = `backtick`;
const d = 'it\'s';
const e = "it's";
const f = 'say "hi"';
const g = "say \"hi\"";
const h = `it's`;
const i = `say "hi"`;
const j = `both ' and "`;
const k = 'both \' and "';
const l = `${value}`;
const m = tag`tagged`;
const n = `multi
line`;
const o = `escaped \
newline`;
const p = 'dollar ${brace}';
const q = "dollar ${brace}";
const r = 'back`tick';
const s = 'escaped \` backtick';
const t = '\\';
const u = 'tab\tand\nnewline';
const v = 'unicode é é';
const w = '';
const x = "";
const y = ``;
const z = ('parens');
(`statement`);
`statement`;

function directives() {
	'use strict';
	`not a directive`;
	return 'x';
}

const object = {
	'key': 1,
	"other": 2,
	['computed']: 3,
	'method'() {},
};

import fs from 'node:fs';
import { 'string name' as alias } from './mod';
export { alias as 'exported name' };
export * as 'star name' from './mod';
export * from "./mod";
import json from './data.json' with { type: 'json' };
export { fs, json };
import foo = require('foo');

type Imported = import('node:fs').Stats;
type Literal = 'literal';
type TemplateType = `template`;
interface Shape {
	'prop': string;
	'method'(): void;
}
declare module 'module-name' {}
enum Enum {
	'member' = 'value',
}
class Klass {
	'field' = 'init';
	'method'() {}
	accessor 'acc' = 1;
	static 'stat' = 2;
	['computed'] = 3;
}
abstract class Abstract {
	abstract 'abstractField': string;
	abstract 'abstractMethod'(): void;
}
const nested = `outer ${`inner`} ${'str'}`;
switch (value) {
	case 'x':
		break;
}
