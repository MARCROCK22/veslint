// prefer-as-const: a literal asserted or annotated with the literal type of the same raw text. An
// assertion (`as`, `<T>`) is fixed to `const`; an annotated variable or class field gets a
// suggestion.
let a = 'a' as 'a';
let b = <'b'>'b';
let c = 1 as 1;
let d = true as true;
let e = 10n as 10n;
let f = ('f') as ('f');
let g: 'g' = 'g';
let h: 2 = (2);
let i: false = false;
class C {
  j: 'j' = 'j';
  static k: 3 = 3;
  readonly l?: 'l' = 'l';
}

// A different raw text, or not a literal type.
let m = 'm' as "m";
let n = 1.0 as 1;
let o = -1 as -1;
let p = null as null;
let q = `q` as `q`;
let r = 'r' as const;
let s: 'x' | 'y' = 'x';
let t = 't' satisfies 't';
class D {
  accessor u: 'u' = 'u';
  v: 'v' | 'w' = 'v';
}

export { a, b, c, d, e, f, g, h, i, C, m, n, o, p, q, r, s, t, D };
