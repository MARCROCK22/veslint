declare let a: any, b: any, c: any, x: any;
for (let i = (a in b); ;) { break; }
for (let i = ((a in b)); ;) { break; }
for (let i = (a in b) ? 1 : 2; ;) { break; }
for (let i = a ? (b in c) : 2; ;) { break; }
for (let i = [(a in b)]; ;) { break; }
for (let i = call((a in b)); ;) { break; }
for (x = (a in b); ;) { break; }
for ((a, (b in c)); ;) { break; }
for (let i = ((a in b) && c); ;) { break; }
for (let i = (x[(a in b)]); ;) { break; }
for (let i = () => { for (let j = (a in b); ;) { break; } return (a in b); }; ;) { break; }
for (let i = (function () { return (a in b); }); ;) { break; }
for (let i = `${(a in b)}`; ;) { break; }
for (let i = { k: (a in b) }; ;) { break; }
for (let i = ((a, b) in c); ;) { break; }
for (let i = (a as any); ;) { break; }
for ((a as any); ;) { break; }
declare function call(...args: unknown[]): any;
