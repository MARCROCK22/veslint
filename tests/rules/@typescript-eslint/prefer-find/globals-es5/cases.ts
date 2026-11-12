// With `lib: ["es5"]` no lib declares BigInt, but it is a global of ESLint's ecmaVersion.
declare const list: number[];
list.filter(x => x > 1)[BigInt(0) as unknown as number];
list.filter(x => x > 1)[Number('0')];
