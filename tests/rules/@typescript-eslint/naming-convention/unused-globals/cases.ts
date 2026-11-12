// naming-convention with the `unused` modifier, for a class expression: its name is looked up from
// the scope around it, where the class is not, so what `unused` asks about is a global with that
// name. A global ESLint declares (for the ecmaVersion, or a `/* global */` comment) is unused
// unless something references it or an `/* exported */` comment names it; an implicit variable of
// a lib never is, and a name that is no variable is not unused either.
/* global declaredUnused, declaredUsed, declaredExported, declaredOff: off, declaredWritable: writable */
/* exported declaredExported, isFinite, 'quotedExport' */
/* global quotedExport */
declaredUsed;
parseFloat('1');
export const a = class declaredUnused {};
export const b = class declaredUsed {};
export const c = class declaredExported {};
export const d = class declaredOff {};
export const e = class declaredWritable {};
export const f = class notDeclared {};
export const g = class Partial {};
export const h = class Array {};
export const i = class isNaN {};
export const j = class isFinite {};
export const k = class parseFloat {};
export const l = class quotedExport {};
export const m = class NodeListOf {};
export const n = class globalThis {};
// A class declaration is a variable of its own scope, whatever the globals.
class declaredUnusedToo {}
/* global declaredUnusedToo */
// The global is `for (x in y) return;`'s variable when nothing declares it.
/* global loopKey, otherKey */
export function keys(object: object) {
  for (loopKey in object) return;
}
export const o = class loopKey {};
export const p = class otherKey {};
