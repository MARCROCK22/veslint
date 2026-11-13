declare const a: any;

// Reported.
location.href = 'javascript:void(0)';
const b = 'JavaScript:alert(1)';
const c = `javascript:x`;

// Not reported.
const d = 'https://example.com';
const e = a`javascript:x`;
const f = `javascript:${a}`;
