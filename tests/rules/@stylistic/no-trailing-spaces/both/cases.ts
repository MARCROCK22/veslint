// Trailing white space of every kind.   
const a = 1;  
const b = 2;	
const c = 3; 
const d = 4;　  
   
	

const e = `line one   
line two	
${a}   
end`;   
type T = `x  
y`;  
/* block comment   
   still the comment   
*/   
// line comment  
const f = 'ü';   // trailing after a comment?   
const g = 5;   
const h = 6;
const i = 7;  const j = '😀';   const k = 8;
const l = 9;﻿
export { a, b, c, d, e, f, g, h, i, j, k, l };
export type { T };   