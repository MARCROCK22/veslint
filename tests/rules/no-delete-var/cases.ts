declare let a: any;

// Reported (TypeScript reports it too).
// @ts-expect-error
delete a;
// @ts-expect-error
delete (a);

// Not reported.
delete a.b;
delete a['c'];
