// This file is not valid UTF-8 on purpose: ESLint lints the text Node decodes from it, with U+FFFD
// in the place of each ill-formed sequence, and the columns after one follow that text.
declare function work(): Promise<number>;
// a lone Latin-1 byte
/* aéb */ work();
const s231 = 'xéy'; work();
// a byte that starts nothing
/* aÿb */ work();
const s300 = 'xÿy'; work();
// a lone continuation byte
/* a€b */ work();
const s376 = 'x€y'; work();
// a truncated three-byte sequence: one U+FFFD
/* aâ‚b */ work();
const s450 = 'xâ‚y'; work();
// a truncated four-byte sequence: one U+FFFD
/* ağŸ˜b */ work();
const s545 = 'xğŸ˜y'; work();
// an overlong form: two
/* aÀ¯b */ work();
const s641 = 'xÀ¯y'; work();
// an overlong form: three
/* aà€¯b */ work();
const s714 = 'xà€¯y'; work();
// a surrogate: three
/* aí €b */ work();
const s791 = 'xí €y'; work();
// above U+10FFFF: four
/* aô€€b */ work();
const s863 = 'xô€€y'; work();
work(); // valid text after them: cafÃ© ğŸ‰
export {};
