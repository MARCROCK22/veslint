// This file is not valid UTF-8 on purpose: ESLint lints the text Node decodes from it, with U+FFFD
// in the place of each ill-formed sequence, and the columns after one follow that text.
declare const anyValue: any;
// a lone Latin-1 byte
/* é */ anyValue.after;
anyValue['ké'];
anyValue[`té`].deep;
// a byte that starts nothing
/* ÿ */ anyValue.after;
anyValue['kÿ'];
anyValue[`tÿ`].deep;
// a lone continuation byte
/* € */ anyValue.after;
anyValue['k€'];
anyValue[`t€`].deep;
// a truncated three-byte sequence: one U+FFFD
/* â‚ */ anyValue.after;
anyValue['kâ‚'];
anyValue[`tâ‚`].deep;
// a truncated four-byte sequence: one U+FFFD
/* ğŸ˜ */ anyValue.after;
anyValue['kğŸ˜'];
anyValue[`tğŸ˜`].deep;
// an overlong form: two
/* À¯ */ anyValue.after;
anyValue['kÀ¯'];
anyValue[`tÀ¯`].deep;
// an overlong form: three
/* à€¯ */ anyValue.after;
anyValue['kà€¯'];
anyValue[`tà€¯`].deep;
// a surrogate: three
/* í € */ anyValue.after;
anyValue['kí €'];
anyValue[`tí €`].deep;
// above U+10FFFF: four
/* ô€€ */ anyValue.after;
anyValue['kô€€'];
anyValue[`tô€€`].deep;
anyValue.end; // valid text after them: cafÃ© ğŸ‰
export {};
