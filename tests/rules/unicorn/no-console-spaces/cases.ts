// unicorn/no-console-spaces: console.log separates its arguments with a space already.
declare const value: unknown;

console.log('a ', value);
console.log(value, ' b');
console.info('a ', ' b', ' c ');
console.warn(`x `, value);
console.error(value, ` y`);
console.debug('é ', value);

// Not reported.
console.log('a  ', value);
console.log(value, '  b');
console.log(' a', value);
console.log(value, 'b ');
console.log(' ');
console.dir('a ', value);
console.log?.('a ', value);
console['log']('a ', value);
