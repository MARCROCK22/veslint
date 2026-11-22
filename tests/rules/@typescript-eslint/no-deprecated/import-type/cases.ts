// The names after `import('…')` in a type are the qualifier of a TSImportType (an Identifier or a
// TSQualifiedName), no member access.
export type A = typeof import('./other').old;
export type B = typeof import('./other').ns.old;
export type C = typeof import('./other').gone.value;
export type D = typeof import('./other').fresh;
export type E = typeof import('./other').ns.fresh;
import { old, ns } from './other';
export const g = old + ns.old;
