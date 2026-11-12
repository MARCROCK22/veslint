// The indentation of the cases the suggestion adds is the column of the last case, or of the
// switch without cases, counted from the last line break: here a lone CR, U+2028, U+2029 and
// CRLF (see no-floating-promises/line-breaks).
declare const value: 'a' | 'b' | 'c';
switch (value) {  case 'a':    break;}
switch (value) {     case 'a':       break; }
switch (value) {       case 'a':         break; }
switch (value) {
        case 'a':
          break;
}
void 0;  switch (value) {  }
void 0;     /* 😀 */ switch (value) {     }
