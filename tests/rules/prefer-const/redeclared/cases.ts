// Names declared again (TypeScript rejects it, ESLint lints it): each `let` declaration counts, as
// getDeclaredVariables gives its variables, whatever declared the name first.
const s1 = 1;
declare let s1: any;
let z;
let z = 1;
declare let w: any;
const w = 1;
const q = 1;
let q;
q = 2;
let [m, n] = [1, 2];
let m;
let k = 1;
let k = 2;
export {};
