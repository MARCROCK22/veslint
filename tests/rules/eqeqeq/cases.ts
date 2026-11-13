declare const a: any;
declare const b: any;

// Reported with "always": a fix when both sides have one type, a suggestion otherwise.
if (a == b) {}
if (a != b) {}
if (typeof a == 'string') {}
if ('x' != 'y') {}
if (1 == 2) {}
if (a == null) {}
if (true == false) {}
if (/re/ == null) {}
if ((a) /* c */ == (b)) {}

// Not reported.
if (a === b) {}
if (a !== null) {}
