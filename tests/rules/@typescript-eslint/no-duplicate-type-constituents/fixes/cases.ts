type A1 = string | string;
type A2 = string | number | string;
type A3 = | string | number | string;
type A4 = string | (string);
type A5 = string | ((string)) | number;
type A6 = string | /* c */ (number) | /* d */ ( number );
type A7 = (string | number) & (string | number);
type A8 = string | (string | number);
type A9 = string | (number | string);
type A10 = { a: 1 } & { a: 1 };
type A11 =
  | 'a'
  | 'b'
  | 'a';
type A12 = string | number // comment
  | string;
function f1(a?: undefined | string) {}
function f2(a?: string | undefined) {}
function f3(a?: | undefined | string) {}
function f4(a?: (undefined) | string) {}
function f5(a?: string | (undefined)) {}
function f6(a?: ( /* inner */ undefined ) | string) {}
const emoji = '🎉é'; type A13 = string | string;
type A14 = (string) | (string);
type A15 = ((string)) | number | ((string));
type A16 = string | (number) | (string | number);
type A17 = string | ((string) | number);
type A18 = Array<string> & Array<string> & { length: number } & Array<string>;
type A19 = string | number | string | number | string;
type A20 = (() => void) | (() => void);
type A21 = string
  | number
  | string  // trailing
  | boolean;
export type { A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11, A12, A13, A14, A15, A16, A17, A18, A19, A20, A21 };
void [f1, f2, f3, f4, f5, f6, emoji];
