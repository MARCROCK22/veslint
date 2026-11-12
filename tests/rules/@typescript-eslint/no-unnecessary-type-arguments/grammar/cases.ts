// The type arguments of an import type and of a type query belong to an ImportType and a
// TypeQuery, which the rule does not look at; those of a `new` and of a call are checked.
type Imported = import('./mod').Box<string>;
type ImportedOther = import('./mod').Box<number>;
type Queried = typeof import('./mod').generic<string>;
type Nested = Array<import('./mod').Box<string>>;
declare const Ctor: typeof import('./mod').Box;
declare const generic: typeof import('./mod').generic;
const made = new Ctor<string>();
const madeOther = new Ctor<number>;
const instantiated = generic<string>;
const negated = !generic<string>;
const called = !generic<string>('a');
export { made, madeOther, instantiated, negated, called };
export type { Imported, ImportedOther, Queried, Nested };
