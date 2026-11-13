declare const a: any;

// Reported without allowKeywords.
const b = a.class;
const c = a?.delete;
const d = a['e'];

// Not reported.
const f = a['class'];
const g = a['ignoredPattern'];
