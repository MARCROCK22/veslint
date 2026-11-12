// valid-typeof with its default options.
declare const x: unknown;
declare const kind: string;

// Valid types, in every equality and on either side.
if (typeof x === 'string') {}
if ('number' == typeof x) {}
if (typeof x !== `bigint`) {}
if ((typeof x) != ('object')) {}
if (typeof x === kind) {}
if (typeof x === typeof kind) {}

// Invalid values: a misspelled type, other literals, a static template.
if (typeof x === 'strnig') {}
if ('fucntion' !== typeof x) {}
if (typeof x == `nunber`) {}
if (typeof x === 'String') {}
if (typeof x === 1) {}
if (typeof x === null) {}
if (typeof x === true) {}
if (typeof x === /object/) {}
if ((typeof x) === ('undefned')) {}
const description = typeof x === 'nmber' ? 'number' : 'other';

// The global undefined, with its suggestion.
if (typeof x === undefined) {}
if (undefined !== typeof x) {}

// Not the global undefined: a parameter, a local constant and a module variable shadow it.
function shadowed(undefined: string) {
  return typeof x === undefined;
}
{
  const undefined = 'undefined';
  if (typeof x === undefined) {}
}

// Not an equality, or not typeof: nothing.
if (typeof x < 'strnig') {}
if (typeof x + 'strnig') {}
if (void x === 'strnig') {}
if ((typeof x as string) === 'strnig') {}
