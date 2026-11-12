// no-useless-empty-export: with another export or import in the file, every empty export (no
// specifiers, no declaration) is reported and removed.
export const a = 1;
export {};
export {} from './cases';
export type {};
export /* inside */ { /* empty */ } ;
export { a as b };

declare module 'inner' {
  export const c: number;
  export {};
}

namespace N {
  export const d = 1;
  export {};
}
