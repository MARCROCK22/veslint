declare let a: any;

// Reported.
const o1 = new Object();
const o2 = Object();
const o3 = new Object;
const f = () => Object();
Object();
a
new Object();

// Not reported.
const o4 = new Object(1);
const o5 = {};
function shadow(Object: any) {
  return new Object();
}
