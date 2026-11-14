declare const x: any;

// Reported.
const a = function () {
  return 1;
}.bind(x);
const b = (() => 1).bind(x);
const c = function () {
  return () => 1;
}.bind(this);
const d = (function () {}).bind(x);
const e = function () {}.bind(x.y);
const f = function () {
  function inner(this: any) {
    return this;
  }
}.bind(x);

// Not reported.
const g = function () {
  return this;
}.bind(x);
const h = function () {
  return () => this;
}.bind(x);
const i = function () {}.bind(x, 1);
const j = function () {}.bind(...[x]);

// Class field initializers and static blocks have their own `this`; a computed key does not
// (10.15.0).
const cf1 = function () { class C { field = this; } return C; }.bind(a);
const cf2 = function () { class C { static field = this; } return C; }.bind(a);
const cf3 = function () { class C { static { this.toString(); } } return C; }.bind(a);
const cf4 = function () { class C { [this.toString()] = 1; } return C; }.bind(a);
const cf5 = function () { class C { accessor field = this; } return C; }.bind(a);
