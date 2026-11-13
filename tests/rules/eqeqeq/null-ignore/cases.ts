declare const a: any;

// Reported with null "ignore".
if (a == 1) {}

// Not reported.
if (a == null) {}
if (a === null) {}
