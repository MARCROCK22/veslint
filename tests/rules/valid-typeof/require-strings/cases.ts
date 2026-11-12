// valid-typeof with requireStringLiterals: only string literals and typeof.
declare const x: unknown;
declare const kind: string;

if (typeof x === kind) {}
if (typeof x === 'number') {}
if (typeof x === `string`) {}
if (typeof x === typeof kind) {}
if (typeof x === undefined) {}
if (typeof x === 'num' + 'ber') {}
if (typeof x === `${kind}`) {}
if (typeof x === (kind as 'string')) {}
if (typeof x === 'strnig') {}
