declare const a: any;
declare const b: any;

// Reported with "smart".
if (a == b) {}
if (a != 1) {}

// Not reported.
if (typeof a == 'string') {}
if ('x' == 'y') {}
if (a == null) {}
if (null != a) {}
