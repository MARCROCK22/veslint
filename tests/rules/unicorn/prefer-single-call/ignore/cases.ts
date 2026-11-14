declare const list: number[];
declare const element: HTMLElement;
declare const other: { push(value: number): void };
declare function value(): number;
declare function importScripts(...urls: string[]): void;

// Fixed.
list.push(1);
list.push(2);
list.push(3, 4)
list.push(5);
list.unshift(1);
list.unshift(2);
element.classList.add('a');
element.classList.add('b');
element.classList.remove('a');
element.classList.remove('b');
importScripts('a.js');
importScripts('b.js');
list.push();
list.push(6,);

// Suggestions.
list.push(value());
list.push(value());
other.push(1);
other.push(2);
list.push(list.length);
list.push(1);

// Not fixed (a comment between).
list.push(1);
// c
list.push(2);

// Not reported.
list.push(1);
console.log(list);
list.push(2);
this.push?.(1);
const s = new Set<number>();
s.add(1);
s.add(2);
list?.push(1);
list?.push(2);
export {};
