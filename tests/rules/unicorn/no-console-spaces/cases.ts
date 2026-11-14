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

// 79.0.0: an escaped trailing space is part of an escape sequence.
console.log('a\ ', "def");
console.log('\ ', "def");
console.log("a\\\ ", "def");
console.log(`a\ `, "def");
console.log("a\\ ", "def");
