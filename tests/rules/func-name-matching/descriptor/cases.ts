declare const obj: any;

// Reported with considerPropertyDescriptor.
Object.defineProperty(obj, 'foo', { value: function bar() {} });
Reflect.defineProperty(obj, 'foo', { value: function bar() {} });
Object.defineProperties(obj, { foo: { value: function bar() {} } });
Object.create(obj, { foo: { value: function bar() {} } });

// Not reported.
Object.defineProperty(obj, 'foo', { value: function foo() {} });
Object.defineProperties(obj, { foo: { value: function foo() {} } });
const o = { value: function value() {} };
