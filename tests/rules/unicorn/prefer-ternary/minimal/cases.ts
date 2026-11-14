// unicorn/prefer-ternary of 79.0.0: branches with one varying part become a minimal ternary
// (`call(test ? a : b)`), with type information deciding whether factoring them is safe; an
// initialized `let` followed by an `if` that reassigns it gets a suggestion; early returns and
// readability checks.
declare let test: boolean, a: number, b: number, shared: number, result: number;
declare let object: { method(value: number): void; a: number; b: number; [key: string]: unknown };
declare function call(value: number, other?: number): number;
declare function check(): boolean;
declare function save(value: number): Promise<void>;
declare let events: string[];

// Minimal ternaries.
if (test) { call(a); } else { call(b); }
if (test) { object.method(a); } else { object.method(b); }
function m1() {
  if (test) { throw new Error('foo'); } else { throw new Error('bar'); }
}
async function m2() {
  if (test) { await save(a); } else { await save(b); }
}
function* m3() {
  if (test) { yield a + 1; } else { yield b + 1; }
}
if (test) { new Date(a); } else { new Date(b); }
if (test) { a + 1; } else { b + 1; }
if (test) { 1 + a; } else { 1 + b; }
if (test) { object[a]; } else { object[b]; }
if (test) { ({a: 1}); } else { ({a: 2}); }
if (test) { [1, a]; } else { [1, b]; }
if (test) { result = call(a); } else { result = call(b); }
function m4() {
  if (test) { return call(a); } else { return call(b); }
}
function m5() {
  if (test) { return call(a); } return call(b);
}
function m6() {
  if (check()) { return call(a); } return call(b);
}
if (check()) { result = call(a); } else { result = call(b); }
async function m7() {
  if (test) { await (a + 1); } else { await (b + 1); }
}
function* m8() {
  if (test) { yield* [call(a)]; } else { yield* [call(b)]; }
}
async function* m9() {
  if (test) { yield await call(a); } else { yield await call(b); }
}
async function m10() {
  if (test) { return await call(a); } else { return await call(b); }
}
function m11() {
  if (test) { throw {a: 1}; } else { throw {a: 2}; }
}
let ready = false;
if (ready = check()) { [1, a]; } else { [1, b]; }
if (check(), ready) { [a]; } else { [b]; }
async function m12() {
  if (await check()) { [a]; } else { [b]; }
}
if (test) { call((a)); } else { call((b)); }
if (test) { object[(a, b)]; } else { object[(b, a)]; }
if (test) { call(a, shared); } else { call(b, shared); }
if (test) { call(shared, a); } else { call(shared, b); }
if (test) { call(a, 1); } else { call (b, 1); }
if (test) { call(
  a,
); } else { call(b); }
check()
if (test) { [a]; } else { [b]; }
check()
if (test) { a + 1; } else { b + 1; }
check()
if (test) { ({a: 1}); } else { ({a: 2}); }
if (test as boolean) { [a]; } else { [b]; }
if (test satisfies boolean) { [a]; } else { [b]; }
// Reported without a fix: the condition or a shared part cannot move, or comments.
if (check()) { call(a); } else { call(b); }
if (test) { call(call(1), a); } else { call(call(1), b); }
if (test) { call(/* keep */ a); } else { call(b); }
if (test) { call(a); } else { /* keep */ call(b); }
if (test) { object./* keep */method(a); } else { object.method(b); }
if (check()) { object[a]; } else { object[b]; }
// Not reported.
if (test) { call(a); } else { save(b); }
if (test) { call(a, b); } else { call(b, a); }
if (test) { call(a); call(b); } else { call(a); }
if (test) { object?.method(a); } else { object?.method(b); }
if (test) { object.a; } else { object.b; }
if (test) { call(test ? a : b); } else { call(b); }
if (test) { call(...[a]); } else { call(...[b]); }
if (test) { ({a: 1}); } else { ({b: 1}); }
if (test) { [a, , 1]; } else { [b, , 1]; }
function* m13() {
  if (test) { yield* [a]; } else { yield [b]; }
}
if (test) { call([
  a,
]); } else { call([
  b,
]); }

// Type information.
declare function one(value: number): void;
declare function lit(value: 'a'): void;
declare function lit(value: 'b'): void;
declare function gen<Value>(value: Value): Value;
declare function rest(...values: number[]): void;
if (test) { one(a); } else { one(b); }
if (test) { lit('a'); } else { lit('b'); }
if (test) { gen(1); } else { gen('b'); }
if (test) { rest(1); } else { rest(2); }
type Thing = { type: 'a'; property: number } | { type: 'b'; property: string };
function t1(type: Thing['type']) {
  if (type === 'a') { throw {type, property: 0}; } else { throw {type, property: ''}; }
}
function t2(type: Thing['type']): Thing {
  if (type === 'a') { return {type, property: 0}; } else { return {type, property: ''}; }
}
function t3(sharedValue: number) {
  if (check()) { throw {sharedValue, value: 1}; } else { throw {sharedValue, value: 2}; }
}
function t4(sharedValue: number) {
  if (test) { throw {sharedValue, value: 1}; } else { throw {sharedValue, value: 2}; }
}
declare class Item { constructor(value: number, other: string) }
declare function call2(value: number, other: string): void;
function t5(item: { kind: 'first'; values: { first: string } } | { kind: 'second'; values: { second: string } }) {
  let value;
  if (item.kind === 'first') { call2(1, item.values[item.kind]); } else { call2(2, item.values[item.kind]); }
  if (item.kind === 'first') { new Item(1, item.values[item.kind]); } else { new Item(2, item.values[item.kind]); }
  if (item.kind === 'first') { value = [1, item.values[item.kind]]; } else { value = [2, item.values[item.kind]]; }
  if (item.kind === 'first') { return 1 + item.values[item.kind]; } else { return 2 + item.values[item.kind]; }
}
function t6(selected: boolean, item: { value: string }) {
  if (selected) { call2(1, item.value); } else { call2(2, item.value); }
}
type Handler = (value: number) => string;
function t7(item: { kind: 'first' | 'second'; handler: Handler }, callback: Handler, firstCallback: Handler, secondCallback: Handler) {
  if (item.kind === 'first') { (callback = firstCallback); } else { (callback = secondCallback); }
  if (item.kind === 'first') { ([item.handler] = [value => value.toFixed()]); } else { ([item.handler] = [value => value.toExponential()]); }
  if (item.kind === 'first') { ({handler: item.handler} = {handler: value => value.toFixed()}); } else { ({handler: item.handler} = {handler: value => value.toExponential()}); }
}
function t8(item: { kind: 'number'; handler: (value: number) => string } | { kind: 'string'; handler: (value: string) => string }) {
  let value;
  if (item.kind === 'number') { ([item.handler] = [value => value.toFixed()]); } else { ([item.handler] = [value => value.toUpperCase()]); }
  if (item.kind === 'number') { value = ([item.handler] = [value => value.toFixed()]); } else { value = ([item.handler] = [value => value.toUpperCase()]); }
  return value;
}
function t9(selected: boolean, callback: (value: number) => string) {
  if (selected) {
    callback = value => value.toFixed();
  } else {
    callback = value => value.toExponential();
  }
  return callback;
}
function t10(item: { kind: 'first'; values: { first: string } } | { kind: 'second'; values: { second: string } }) {
  let value: string;
  if (item.kind === 'first') { ([value = item.values[item.kind]] = []); } else { ([value = item.values[item.kind]] = []); }
  return value;
}
const enum First { value }
const enum Second { value }
if (test) { First.value; } else { Second.value; }

// `let` followed by an `if`: only with a type annotation when there is type information.
function l1(selected: boolean) {
  let value = 1;
  if (selected) { value = 2; }
  return value;
}
function l2(selected: boolean) {
  let value: number = 1;
  if (selected) { value = 2; }
  return value;
}
function l3(selected: boolean) {
  let value: Array<(value: number) => string> = [(value: number) => value.toFixed()];
  if (selected) { value = [value => value.toExponential()]; }
  return value;
}
function l4(selected: boolean, data: number[], defaults: number[]) {
  let items: number[] = defaults;
  if (data.length) {
    items = data;
  }
  let later: number[] = defaults;
  if (selected) {
    later = data;
  }
  later = [];
  let parenthesized: number[] = (defaults);
  if (selected) parenthesized = data;
  return [items, later, parenthesized];
}
async function l5(selected: boolean, other: Promise<number>) {
  let value: number = 1;
  if (selected) {
    ;;
    value = await other;
    ;;
  }
  return value;
}
function l6(selected: boolean) {
  let value: number = 1
  if (selected) {
    value = 2
  }
  (value)
}
function l7(selected: boolean) {
  let value: number = 1; // default
  if (selected) { value = 2; }
  let other: number = 1;
  // explanation
  if (selected) { other = 2; }
  let third: number = /* explanation */ 1;
  if (selected) { third = 2; }
  return [value, other, third];
}
function l8(selected: boolean, item: { flag: boolean; value: number }) {
  let value: number = item.value;
  if (item.flag) { value = 2; }
  let other: number = 1;
  if (selected) { other = call(1); }
  let handler: () => number = () => 1;
  if (selected) { handler = () => 2; }
  let fromCall: number = call(1);
  if (selected) { fromCall = 2; }
  let x: number = 1;
  if (x) { x = 2; }
  let y: number = 1;
  if (selected) { y = y + 1; }
  let z: number = 1;
  if (selected ? a : b) { z = 2; }
  return [value, other, handler, fromCall, x, y, z];
}

// Early returns.
function r1() { if (a) return 1; if (b) return 2; return 3; }
function r2() { if (a) { return; } if (b) { return a; } return b; }
function r3() { if (a) { return a; } call(1); if (b) { return a; } return b; }
function r4() { if (a) { return a; }; if (b) { return a; } return b; }
function r5() { if (a) { call(1); } if (b) { return a; } return b; }
function r6() { if (a) { throw a; } if (b) { return a; } return b; }
function r7() { if (a) { return a; } { if (b) { return a; } return b; } }
function r8() { if (a) { return a; } if (b) { return a; } else { return b; } }
function r9() { if (test) { return a; } return b; }
function r10() { if (test) return a; return; }
function r11() {
  if (test) { return a; }
  // comment
  return b;
}
function r12() {
  if (test) { return a; }
  return b; // comment
}
function r13() { if (test) { return true; } return false; }

// Readability.
function e1() { if (test) { return String(a ? b : 1); } return a; }
function e2() { if (test) { return [a, , b ? 1 : 2]; } return a; }
function e3() { if (test) { return a && b; } return a; }
function e4() { if (test) { return [a].map(item => item ? a : b); } return a; }
function e5() { if (test) { return [a].map(item => { return item; }); } return a; }
function e6() { if (test) { return {
  value: a,
}; } return a; }
function e7() { if (test) { return call(
  a,
  b,
); } return a; }
function e8() { if (test) { return `first
second`; } return 'other'; }
function e9() { if (test) { return (a ? b : 1) as number; } return a; }
if (call(
  a,
)) { result = a; } else { result = b; }
if (Boolean(a ? b : 1)) { result = a; } else { result = b; }
