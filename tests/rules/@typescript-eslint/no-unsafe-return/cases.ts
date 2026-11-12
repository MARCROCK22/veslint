// Cases of no-unsafe-return (typescript-eslint 8.62.0, no options), with strict.
declare const anyValue: any;
declare const list: any[];
declare const anyPromise: Promise<any>;
declare const anyListPromise: Promise<any[]>;
declare const anySet: Set<any>;

function f1() { return anyValue; }
function f2() { return list; }
async function f3() { return anyPromise; }
function f4() { return anyPromise; }
function f5(): unknown { return anyValue; }
function f6(): unknown[] { return list; }
async function f7(): Promise<unknown> { return anyPromise; }
const f8 = () => anyValue;
const f9: () => number = () => anyValue;
function f10(): any { return anyValue; }
function f11(): Set<string> { return new Set<any>(); }
const f12: () => Set<string> = () => new Set<any>();
function f13(): Map<string, number> { return new Map(); }
async function f14(): Promise<number> { return anyValue; }
async function f15() { return anyListPromise; }
function f16(): Set<string> { return anySet; }
const f17 = (): Set<string> => anySet;
function f18(c: boolean) { if (c) { return 1; } return anyValue; }
const f19 = () => missing;
function f20() { return [anyValue]; }
const objectValue = { method() { return anyValue; } };
class SomeClass { method() { return anyValue; } }
[1].map(() => anyValue);
[1].map((): number => anyValue);
void [f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12, f13, f14, f15, f16, f17, f18, f19, f20];
void [objectValue, SomeClass];

// The annotation is an alias of a function type: its type comes from the TypeReference node.
type ReturnsUnknown = () => unknown;
type ReturnsString = () => string;
export const viaAlias: ReturnsUnknown = () => anyValue;
export const viaAliasString: ReturnsString = () => anyValue;
