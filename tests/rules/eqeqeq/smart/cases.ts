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

// Templates without expressions are strings (10.15.0).
if (`a` == `b`) {}
if (`a` != 'b') {}
declare const t1: string;
if (`a${t1}` == 'b') {}
