// unicorn/no-new-buffer: `Buffer.from()` for data and `Buffer.alloc()` for a size instead of the
// deprecated `new Buffer()`.
declare const Buffer: any;
declare const data: unknown;
declare const list: number[];

const b1 = new Buffer('text');
const b2 = new Buffer([1, 2]);
const b3 = new Buffer(`text`);
const b4 = new Buffer(10);
const b5 = new Buffer(list.length);
const b6 = new Buffer(Math.max(1, 2));
const b7 = new Buffer(1 + 2);
const b8 = new Buffer(-1);
const b9 = new Buffer(data, 'utf8');
const size = 4;
const b10 = new Buffer(size);
const b11 = new Buffer(data);
const b12 = new Buffer(...list);
const b13 = new Buffer;
const b14 = new Buffer(data as string);
function f() {
  return new
    Buffer(1);
}

// Not reported.
const z1 = Buffer.from('text');
const z2 = new Buffer.Thing(1);
