export {};
declare function returnsVoid(): void;
declare function returnsNever(): never;
declare function returnsNumber(): number;
declare const neverOrUndefined: never | undefined;

// With checkNever, `never` is meaningless too.
void returnsVoid();
void returnsNever();
void (null as never);
void neverOrUndefined;
void returnsNumber();
