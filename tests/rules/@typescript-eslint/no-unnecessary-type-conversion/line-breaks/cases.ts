// `text + ''` is reported from the end of its left operand: its line and its column are counted
// with a lone CR, U+2028, U+2029 and CRLF as line breaks (see no-floating-promises/line-breaks).
declare const text: string;
void (text + '');void (text + ''); void (text + ''); void (text + '');
void (text + '');
void (text  + ''); void (/* 😀 */ text /* 😀 */   + ''); void ('' + text); void String(text);
void (  text   .toString());
