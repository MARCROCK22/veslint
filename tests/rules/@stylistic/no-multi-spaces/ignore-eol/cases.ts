const a = 1;  // trailing comment
const b = 2;  /* trailing block */
const c = 3;  /* not last */ const d = 4;
const e  = 5;  // still reported before =
export { a, b, c, d, e };  // last
