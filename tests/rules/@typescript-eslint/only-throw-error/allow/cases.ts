class Custom {}
class Derived extends Custom {}
class Other {}
declare const custom: Custom;
declare const derived: Derived;
declare const other: Other;
declare const customOrOther: Custom | Other;
declare const text: string;
declare const response: Response;
declare const url: URL;
declare const date: Date;
function f1() {
  throw custom;
}
function f2() {
  throw derived;
}
function f3() {
  throw other;
}
function f4() {
  throw customOrOther;
}
function f5() {
  throw text;
}
function f6() {
  throw 'literal';
}
function f7() {
  throw response;
}
function f8() {
  throw url;
}
function f9() {
  throw date;
}
function f10() {
  throw new Custom();
}
