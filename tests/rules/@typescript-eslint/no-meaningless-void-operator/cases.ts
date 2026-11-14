export {};
declare function returnsVoid(): void;
declare function returnsUndefined(): undefined;
declare function returnsNumber(): number;
declare function returnsNever(): never;
declare function returnsPromise(): Promise<void>;
declare function returnsVoidOrUndefined(): void | undefined;
declare function returnsMaybeNumber(): number | undefined;
declare const anyValue: any;
declare const unknownValue: unknown;

// Reported: the argument is already void or undefined.
void returnsVoid();
void returnsUndefined();
void undefined;
void returnsVoidOrUndefined();
void (returnsVoid());
void void 0;
const callback = (): void => void returnsVoid();

// Not reported.
void 0;
void returnsNumber();
void returnsPromise();
void returnsMaybeNumber();
void anyValue;
void unknownValue;
void returnsNever();
void (null as never);

// typescript-eslint 8.72: `void` of what is not a call (through assertions, optional chains and
// sequences) is useless, but `void 0`, an assignment and a thenable value; fixed only as a
// statement.
declare let numberValue: number;
declare const promised: Promise<number>;
declare const thenableValue: { then(cb: () => void): void };
declare const holder: { run?: () => number; value: number };
declare function numberCall(): number;
void numberValue;
(void numberValue);
const nonCall1 = void numberValue;
void 0;
void 0x0;
void 0.0;
void 0n;
void 1;
void (numberValue = 1);
void (numberValue += 1);
void (numberValue ||= 1);
void promised;
void thenableValue;
void holder.value;
void holder.run?.();
void (holder.run as () => number)();
void (numberCall() as number);
void (numberCall()!);
void (numberCall() satisfies number);
void (<number>numberCall());
void (0, numberCall());
void (numberCall(), 0);
void `x`;
void String.raw`x`;
void import('./cases');
void new Date();
void numberValue++;
const nonCall2 = () => void numberValue;
export { nonCall1, nonCall2 };
