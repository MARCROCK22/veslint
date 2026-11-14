declare const foo: (...args: unknown[]) => unknown;
declare const bar: {method: (...args: unknown[]) => unknown};
declare const maybe: typeof bar | undefined;

foo.apply(null, [42]);
foo.apply(this, [42]);
foo.apply(null, arguments);
foo['apply'](null, [1, 2]);
foo[`apply`](null, [1, 2]);
bar.method.apply(null, []);
(0, foo).apply(null, [1]);
Function.prototype.apply.call(foo, null, [42]);
Function.prototype.apply.call(foo, this, arguments);
Function.prototype.apply.call((0, foo), null, [42]);
foo.apply(/* keep */ null, [42]);
foo.apply(null, [42] /* keep */);
foo /* lost */.apply(null, [42]);
maybe?.method.apply(null, [1]);
(maybe?.method)!.apply(null, [1]);
function inner(this: unknown) {
	return foo.apply(null, arguments);
}
const typeofCase = typeof foo.apply(null, [1]);

foo.apply(undefined, [42]);
foo.apply(null, args);
foo.apply(null);
foo.apply(null, [42], extra);
foo?.apply(null, [42]);
foo.apply?.(null, [42]);
'string'.apply(null, []);
[].apply(null, []);
({}).apply(null, []);
foo.call(null, 42);
Function.prototype.apply.call(foo, null);
Reflect.apply(foo, null, [42]);

declare const args: unknown[];
declare const extra: unknown;
export {inner, typeofCase};
