// Reported: irregular whitespace outside strings.
const a1 = 1; 
const a2 = 2;
const a3 = 3; const a4 = 4;
/* comment */
const a5 = `x ${a1}`;

// Not reported: inside strings.
const k1 = " ";
const k2 = / /;
