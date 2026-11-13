declare const foo: any;
declare const bar: any;

// Reported.
foo.hasOwnProperty('bar');
foo.isPrototypeOf(bar);
foo.propertyIsEnumerable('bar');
foo.bar.hasOwnProperty('bar');
foo['hasOwnProperty']('bar');
foo?.hasOwnProperty('bar');
(foo, bar).hasOwnProperty('x');
foo.hasOwnProperty();

// Not reported.
Object.prototype.hasOwnProperty.call(foo, 'bar');
foo.hasOwnProperty;
foo[hasOwnProperty]('bar');
declare const hasOwnProperty: string;
