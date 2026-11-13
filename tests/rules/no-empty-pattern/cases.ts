declare const obj: any;

// Reported.
const {} = obj;
const [] = obj;
function f1({}: object) {}
function f2([]: unknown[]) {}
const { a: {} } = obj;
const { b: [] } = obj;
function f3({} = {}) {}
const g = ({}) => {};
let x: any;
({} = obj);
[] = obj;
for (const {} of [obj]) {}

// Not reported.
const { c } = obj;
const [d] = obj;
const [,] = obj;
const { e = {} } = obj;
const h = (y = {}) => y;
