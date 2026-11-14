/* global console */
declare function work(...args: unknown[]): void;
declare let value: number;

// Reported: whitespace before semicolons.
let spaced = 1 ;
work() ;
value = 2	;
work(); value = 3 ;
type Alias = string ;
declare function declared(): void ;
declare function declaredNoType() ;
function overload(a: number): void ;
function overload(a: string): void;
function overload(a: unknown): void {
	work(a) ;
}
for (let i = 0 ; i < 10 ; i++) {
	if (i === 2) break ;
	if (i === 3) continue ;
	if (i === 4) debugger ;
}
do {
	work();
} while (value < 0) ;
function returns(): number {
	return 1 ;
}
function throws(): never {
	throw new Error('x') ;
}
interface Shape {
	name: string ;
	area(): number ;
	new (): Shape ;
	[key: string]: unknown ;
}
class Fields {
	field: string = '' ;
	plain = 1 ;
	accessor kept = 2 ;
	declare declaredField: number ;
	method(): void ;
	method(a?: string): void {
		work(a);
	}
}
abstract class AbstractFields {
	abstract prop: string ;
	abstract method(): void ;
}
export const exported = 1 ;
export type ExportedAlias = number ;
export { spaced } ;
export * from './other' ;
export default value ;
import './side-effect' ;
work(/* comment */) /* comment */ ;
const multiline = `a
b` ;

// Reported: missing whitespace after semicolons.
work();work();
let a1 = 1;let a2 = 2;
for (let j = 0;j < 1;j++) {
	work(j);
}
type First = string;type Second = number;
interface Packed { first: string;second: number; }
class PackedFields { one = 1;two = 2; }

// Reported: whitespace after semicolons.
for (;; ) {
	break;
}

// Not reported.
work(); work();
for (;;) {
	break;
}
for (let k = 0; k < 1; k++) {
	work(k);
}
work()
;work()
const afterTemplate = `x
`;work();
{ work(); }
if (value) { work() }
const arrow = () => { return 1; };
label: for (;;) { break label; }

export { a1, a2, multiline, arrow, afterTemplate, Fields, AbstractFields, returns, throws, overload, declared, declaredNoType };
export type { Alias, Shape, First, Second, Packed, PackedFields };
