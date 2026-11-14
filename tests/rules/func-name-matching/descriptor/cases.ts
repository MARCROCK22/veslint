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

// String keys, keys that are not identifiers and descriptors in other places (10.15.0).
Object.defineProperties(obj, { 'foo': { value: function bar() {} } });
Object.defineProperties(obj, { ['foo']: { value: function bar() {} } });
Object.defineProperties(obj, { 'not an id': { value: function bar() {} } });
Object.defineProperty(obj, 'not an id', { value: function bar() {} });
Object.defineProperty(obj, `foo`, { value: function bar() {} });
Object.create(obj, { foo: { 'value': function bar() {} } });
Object?.defineProperty(obj, 'foo', { value: function bar() {} });
Object.defineProperty(obj, { value: function bar() {} }, {});
Object.defineProperty({ value: function bar() {} }, 'foo', {});
Object.assign(obj, { value: function bar() {} });
function shadowed(Object: any) {
  Object.defineProperty(obj, 'foo', { value: function bar() {} });
}
