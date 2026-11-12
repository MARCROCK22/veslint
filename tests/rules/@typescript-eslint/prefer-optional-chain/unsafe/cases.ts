// prefer-optional-chain with allowPotentiallyUnsafeFixesThatModifyTheReturnTypeIKnowWhatImDoing:
// a fix where the default only suggests it. `(x || {}).y` is still a suggestion.
type Strict = { bar: { baz: { qux: number } } };
declare const strict: Strict | null;
strict && strict.bar;
strict && strict.bar && strict.bar.baz;
strict !== null && strict.bar.baz.qux;
!strict || strict.bar.baz;
(strict || {}).bar;
