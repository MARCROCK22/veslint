(und && und.bar && cond) && und;
'😀'; (und && und.bar && cond) && und && und.bar && cond && und.bar && cond && und && cond;
// prefer-optional-chain: a `(` of the report range that closes after it. The fixer then replaces
// the whole expression and reads its text with offsets of the file, which is only right for the
// first statement; the second one checks that veslint is wrong in the same way.
declare const und: { bar?: number } | undefined;
declare const cond: boolean;
