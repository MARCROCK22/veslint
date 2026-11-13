declare const o: any;

// Reported.
o.__iterator__ = () => {};
const a = o['__iterator__'];
const b = o[`__iterator__`];

// Not reported.
const c = o.iterator;
const d = o[Symbol.iterator];
