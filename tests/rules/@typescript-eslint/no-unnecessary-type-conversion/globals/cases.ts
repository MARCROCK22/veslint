// `/* global */` comments and lib names give ESLint variables without definitions.
/* global String, Number:off */
declare const text: string;
declare const count: number;
declare const flag: boolean;
String(text);
Number(count);
Boolean(flag);
function shadowed(String: (value: string) => string) {
  String(text);
}
export { shadowed };
