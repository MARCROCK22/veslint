declare const obj: any;
declare let module: any;
let x: any;

// Reported with "always".
const a = function b() {};
x = function y() {};
obj.p = function q() {};
obj['r'] = function s() {};
const o = { t: function u() {}, 'v': function w() {}, ['k']: function k2() {} };
class C {
  m = function n() {};
}

// Not reported.
const c = function c() {};
const d = () => {};
obj[x] = function z() {};
module.exports = function e() {};
module['exports'] = function e2() {};
const o2 = { 'not-an-identifier': function f() {}, 'class': function g() {} };
obj.default = function h() {};
