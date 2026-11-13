declare const obj: any;

// Reported.
Object.prototype.hasOwnProperty.call(obj, 'a');
({}).hasOwnProperty.call(obj, 'a');
Object.hasOwnProperty.call(obj, 'a');
const a = !Object.prototype.hasOwnProperty.call(obj, 'a');
const b = Object['prototype']['hasOwnProperty']['call'](obj, 'a');

// Not reported.
Object.hasOwn(obj, 'a');
obj.hasOwnProperty.call(obj, 'a');
Object.prototype.hasOwnProperty.apply(obj, ['a']);
