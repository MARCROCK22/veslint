// U+2028 ends this comment, const lbAfterLs = 1;
// U+2029 this one, const lbAfterPs = 2;
// and a lone CR this one.const lbAfterCr = 3;
/* U+2028 , U+2029 , a lone CR and CRLF
 */ const lbAfterBlock = 4;
const lbString = 'a b c', lbAfterString = "\";const lbTemplate = `  
${lbString}`, lbAfterTemplate = lbAfterLs; function lbFunction(lbParam: number,   lbOther?: string) {  return lbParam;
}const lbEmoji = "🎉"; /* 🎉 */ const lbAfterEmoji = lbFunction( lbAfterCr);
