declare const a: any;

// Reported.
if (a == null) {}
if (null != a) {}
const b = (a) == (null);

// Not reported.
if (a === null) {}
if (a == undefined) {}
