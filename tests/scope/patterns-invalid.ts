// Targets TypeScript rejects but parses: PatternVisitor walks every child.
declare let a: any, b: any, c: any, f: any;
[a + b] = c;
[f(a, b)] = c;
[-a] = c;
[a ? b : c] = f;
[`t${a}`] = c;
[a?.b] = c;
[{ k: a }.k] = c;
[this] = c;
[new f(a)] = c;
[(a, b)] = c;
export {};
