// An access is not reported when its object is a member access that is unsafe already: only the
// first one of a chain is. An optional chain in parentheses is a ChainExpression for ESTree, not
// a member access, so the access after it is reported too.
declare const anything: any;
declare const key: string;

// Two reports: the chain ends at the parentheses.
(anything?.a).b;
(anything?.[key]).c;
(anything?.a.b).c;
((anything?.a)).d;

// One report: one chain.
anything?.a.b;
(anything.a).b;
anything?.a?.b.c;
(anything.a)?.b;
anything?.a!.b;
