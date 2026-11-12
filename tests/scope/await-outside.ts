// `await` in a function that is not async: TypeScript reads an identifier where it can.
declare const x: Promise<number>;
function notAsync() { await (x); await [x]; await `t${x}`; await x; }
async function isAsync() { await (x); await [x]; }
export { notAsync, isAsync };
