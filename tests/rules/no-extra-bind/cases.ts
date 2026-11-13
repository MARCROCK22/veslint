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
