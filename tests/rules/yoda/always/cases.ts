declare let a: any;

// Reported with "always" and onlyEquality.
if (a === 'red') {}
if (a == 1) {}

// Not reported.
if ('red' === a) {}
if (a < 1) {}
