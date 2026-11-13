import { readFile as readFile, writeFile } from 'node:fs';
import { 'stat' as stat } from 'node:fs';

declare const obj: any;

// Reported.
const { a: a } = obj;
const { 'b': b } = obj;
const { c: c = 1 } = obj;
const { d: /* comment */ d } = obj;
const { e: e /* inside */ } = obj;
let f: any;
({ f: f } = obj);
function g({ h: h }: any) {}
const i = 1;
export { i as i };
export { i as 'i2', g as 'g' };

// Not reported.
const { j: k } = obj;
const { l } = obj;
const { ['m']: m } = obj;
const { n: { n } } = obj;
const { 1: o } = obj;
export { writeFile, readFile as rf };
