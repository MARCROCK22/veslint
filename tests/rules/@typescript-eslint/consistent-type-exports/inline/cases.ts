// consistent-type-exports: types exported as values.
import { T1, I1 } from './types';
import type { C1 } from './values';
import { type E1, v1, f1, N1, TypeNs } from './values';
import * as valuesNs from './values';
import type * as typeNs from './values';
import Default, { M1, mv1 } from './mixed';
import { Missing } from './missing';
import type TypeDefault from './mixed';

type Local = string;
interface LocalI {}
class LocalC {}
const localV = 1;
enum LocalE {
  A,
}
namespace LocalNs {
  export const a = 1;
}
namespace LocalTypeNs {
  export type A = string;
}
declare const declared: number;
function localF() {}

export { T1 };
export { I1, T1 as T2 };
export { v1 };
export { T1 as T3, v1 as v2 };
export { I1 as I2, T1 as T4, f1 };
export { C1 };
export { E1 as E2 };
export { valuesNs };
export { typeNs };
export { N1, TypeNs };
export { Default, M1, mv1 };
export { TypeDefault };
export { Missing };
export { Local, LocalI };
export { LocalC, localV, LocalE, LocalNs, declared, localF };
export { LocalTypeNs };
export { Local as L2, LocalC as C2 };
export { type Local as L3, LocalI as LI3 };
export { type Local as L4, LocalI as LI4, localV as lv4 };
export { type Local as L5, localV as lv5 };
export type { Local as L6, LocalC as C6 };
export { Local as 'quoted type', localV as 'quoted value' };
export {};

// With a source.
export { T1 as RT1 } from './types';
export { T1 as RT2, I1 as RI2 } from './types';
export { v1 as rv1 } from './values';
export { M1 as RM1, mv1 as rmv1 } from './mixed';
export { M1 as RM2, mv1 as rmv2, M2 as RM3 } from './mixed';
export { default as D2 } from './mixed';
export { Renamed } from './types';
export { C1 as RC1, E1 as RE1, v1 as rv2 } from './reexport';
export { T1 as RT5, I1 as RI5 } from './reexport';
export { Nope } from './missing';
export { type M1 as RM4, M2 as RM5, mv1 as rmv3 } from "./mixed";
export { Ambient } from 'ambient-types';

// Whole modules.
export * from './types';
export * from './values';
export * from './mixed';
export * as nsTypes from './types';
export * as nsValues from './values';
export * from './type-star';
export * as nsTypeStar from './type-star';
export * from './empty';
export * from './missing';
export * from 'ambient-types';
export type * from './values';
export type * as typeStar from './types';

// Other layouts, for the fixes.
export {T1 as F1,v1 as fv1};
export {
  T1 as F2,
  v1 as fv2, // comment
  I1 as F3,
};
export { type /* inline */ Local as L7, LocalI as LI7 };
export { T1 as F4 }
export { /* first */ I1 as F5, /* second */ f1 as ff5 } from './missing-too';
export { T1 as F6, type I1 as F7, v1 as fv6, type Local as F8 };
