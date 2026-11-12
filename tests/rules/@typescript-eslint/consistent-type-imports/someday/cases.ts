// A default import used only as a type, and named imports.
import Foo from 'a1';
let x1: Foo;
import { A2, B2 } from 'a2';
let x2: A2;
B2();
import { C3, D3 } from 'a3';
let x3: C3 | D3;
import * as NS4 from 'a4';
let x4: NS4.T;

// A default import with named ones.
import Def5, { E5 } from 'a5';
let x5: Def5 | E5;
import Def6, { F6 } from 'a6';
let x6: F6;
Def6();
import Def7, * as NS7 from 'a7';
let x7: NS7.T;
Def7();
import Def8, { G8 } from 'a8';
let x8: Def8;
G8();
import Def9, {} from 'a9';
let x9: Def9;

// A type-only import of the same source before and after.
import type { H10 } from 'a10';
import { H11, H12 } from 'a10';
let x10: H10 | H11;
H12();
import { I1, I2 } from 'a11';
import type { I3 } from 'a11';
let x11: I1 | I3;
I2();
import type {} from 'a12';
import { J1 } from 'a12';
let x12: J1;

// Unused and inline type specifiers.
import { K1, K2 } from 'a13';
let x13: K1;
import { type L1, L2 } from 'a14';
let x14: L2;
import { type M1, M2 } from 'a15';
let x15: M1;
M2();

// Value references that count as types: typeof and computed keys of type members.
import { N1 } from 'a16';
type T16 = typeof N1;
import N2 from 'a17';
type T17 = typeof N2.member.deep;
import { O1 } from 'a18';
type T18 = { [O1]: string };
import { O2 } from 'a19';
type T19 = { [O2.key]: string; [O2.other](): void };

// Exports keep the kind of the import.
import { P1 } from 'a20';
export { P1 };
import type { P2 } from 'a21';
export { P2 };
import P3 from 'a22';
export default P3;
import { P4 } from 'a23';
export type { P4 };

// Values: calls, heritage, `new`, namespace members.
import { Q1 } from 'a24';
class X24 extends Q1 {}
import { Q2 } from 'a25';
class X25 implements Q2 {}
import * as NS26 from 'a26';
NS26.run();
import Q3 from 'a27';
new Q3();

// Several groups of type specifiers among values, and comments.
import { R1, R2, R3, R4, R5 } from 'a28';
let x28: R1 | R2 | R4;
R3();
R5();
import { /* first */ S1, S2 /* last */ } from 'a29';
let x29: S1;
S2();
import { S3, S4, } from 'a30';
let x30: S4;
S3();
import {
  S5,
  S6,
  S7,
} from 'a31';
let x31: S6 | S7;
S5();

// Shadowed and generic uses.
import Shadowed from 'a32';
function shadow() {
  type Shadowed = string;
  let local: Shadowed = '';
  return local;
}
import { U1 } from 'a33';
let x33: Array<U1>;

// Import attributes, and `import()` types.
import V1 from 'a34' with { type: 'json' };
let x34: V1;
import * as V2 from 'a35' with {};
let x35: V2.T;
let x36: import('a36').T;
type T37 = typeof import('a37');
type T38 = import('a38').G<import('a39').H>;

// `import x = require()` is not an ImportDeclaration.
import W1 = require('a40');
let x40: W1;

export { x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x28, x29, x30, x31, x33, x34, x35, x36, shadow, X24, X25 };
export type { T16, T17, T18, T19, T37, T38 };
