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
