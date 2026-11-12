// strict-void-return: a program may give call signatures to a primitive through its global
// interface, and then a string is a function that returns a number.
interface String {
  (): number;
}
interface Number {
  (): void;
}
declare function takesVoid(callback: () => void): void;
declare function takesVoidOrText(callback: (() => void) | string): void;
declare const flag: boolean;
const text = 'abc';
const count = 1;
takesVoid(text);
takesVoid('literal');
takesVoid(`template ${count}`);
takesVoid(count);
takesVoid(2);
takesVoid(flag ? text : count);
takesVoidOrText(text);
const assigned: () => void = text;
const assignedNumber: () => void = count;
const list: (() => void)[] = [text, 'x', 3];
const record: { run: () => void; stop: () => void } = { run: 'now', stop: 4 };
function returnsVoidFunction(): () => void {
  return text;
}
class Holder {
  callback: () => void = 'held';
}
