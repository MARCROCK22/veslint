declare const obj: any;
declare const args: unknown[];
declare function foo(...a: unknown[]): void;

// Reported.
foo.apply(undefined, args);
foo.apply(null, args);
obj.foo.apply(obj, args);
obj['foo'].apply(obj, args);
foo['apply'](null, args);

// Not reported.
foo.apply(obj, args);
foo.apply(null, [1, 2]);
obj.foo.apply(null, args);
foo.apply(null, ...[args]);
