declare const obj: any;
declare function foo(...args: unknown[]): void;

// Reported.
foo.call(undefined, 1, 2);
foo.call(void 0, 1);
foo.call(null, 1);
foo.apply(undefined, [1, 2]);
obj.foo.call(obj, 1);
obj.foo.apply(obj, [1]);
obj.a.b.call(obj.a, 1);

// Not reported.
foo.call(obj, 1);
obj.foo.call(null, 1);
obj.foo.apply(obj, args);
foo.call();
obj['foo'].call(obj, 1);
declare const args: unknown[];
