// The indentation the fix gives the comments is the column of the `delete`, counted from the
// last line break: here a lone CR, U+2028, U+2029 and CRLF (see no-floating-promises/line-breaks).
declare const array: string[];
function f(): void {  delete /* after a lone CR */ array[0];     delete /* after U+2028 */ array[1];       delete /* after U+2029 */ array[2];
        delete /* after CRLF */ array[3];
  void 0;   void 1; delete /* 😀 */ array[    // after a statement    4  ];
}
void f;
