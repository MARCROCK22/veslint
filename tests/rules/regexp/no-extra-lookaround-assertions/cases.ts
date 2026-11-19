// Reported, with a fix.
export const a1 = /a(?=b(?=c))/;
export const a2 = /a(?=b(?=c|d))/;
export const a3 = /(?<=(?<=a)b)c/;
export const a4 = /(?<=(?<=a|b)c)d/u;
export const a5 = /x(?=a|b(?=c))/;
export const a6 = new RegExp('é(?=b(?=c))');
export const a7 = /a(?=(?=b(?=c)))/;
// Not reported.
export const b1 = /a(?=b(?!c))/;
export const b2 = /a(?=(?=b)c)/;
export const b3 = /(?<=a(?<=b))c/;
export const b4 = /a(?=b(?<=c))/;
