declare const a: any;

// Reported with null "never".
if (a === null) {}
if (null !== a) {}
if (a == 1) {}

// Not reported.
if (a == null) {}
